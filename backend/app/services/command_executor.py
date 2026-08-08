"""根据解析后的 JSON 执行操作。

优先使用 LLM 从目录树中选出的真实 id 直接定位；
当 id 为空时，回退到按名称模糊查找。

所有异常/未找到场景返回 success=false 和可读 message，不抛 500。
对于重名（多个匹配）：暂取第一个，并在 message 中提示存在多个匹配。
"""

from typing import Any, Optional

from .. import crud
from . import note_generator


def _result(action: str, success: bool, message: str, data: Any = None) -> dict:
    """构造统一结果对象。"""
    return {"action": action, "success": success, "message": message, "data": data}


def _id_or_none(value: Any) -> Optional[str]:
    """把空字符串/None 视为「未提供」，返回 None。"""
    if value is None:
        return None
    v = str(value).strip()
    return v or None


async def execute(parsed: dict) -> dict:
    """根据解析结果执行操作，返回统一结果对象。"""
    action = parsed.get("action", "")
    try:
        if action == "create_note":
            return await _handle_create_note(parsed)
        if action == "create_event":
            return await _handle_create_event(parsed)
        if action == "append_note":
            return await _handle_append_note(parsed)
        if action == "set_reminder":
            return await _handle_set_reminder(parsed)
        if action == "save_place":
            return await _handle_save_place(parsed)
        if action == "create_folder":
            return await _handle_create_folder(parsed)
        if action == "rename":
            return await _handle_rename(parsed)
        if action == "delete":
            return await _handle_delete(parsed)
        if action == "move_file":
            return await _handle_move_file(parsed)
        if action == "locate_folder":
            return await _handle_locate_folder(parsed)
        if action == "list":
            return await _handle_list(parsed)
        return _result(action or "unknown", False, f"不支持的操作: {action}")
    except Exception as e:  # 兜底：任何异常都转为失败结果
        return _result(action, False, f"执行失败: {e}", None)


def _inject_created_ids(step: dict, created: dict[str, str]) -> None:
    """若步骤用名称引用了本批次新建的文件夹，且未提供 id，则注入其 id。

    created: {文件夹名: id}，由前面 create_folder 步骤产出。
    """
    if not created:
        return
    action = step.get("action")
    if action == "move_file":
        if not _id_or_none(step.get("to_folder_id")):
            fid = created.get(step.get("to_folder", ""))
            if fid:
                step["to_folder_id"] = fid
    elif action == "create_note":
        if not _id_or_none(step.get("target_folder_id")):
            fid = created.get(step.get("target_folder", ""))
            if fid:
                step["target_folder_id"] = fid
    elif action == "create_folder":
        if not _id_or_none(step.get("parent_folder_id")):
            fid = created.get(step.get("parent_folder", ""))
            if fid:
                step["parent_folder_id"] = fid
    elif action == "list":
        if not _id_or_none(step.get("target_folder_id")):
            fid = created.get(step.get("path", ""))
            if fid:
                step["target_folder_id"] = fid


async def execute_steps(steps: list[dict]) -> dict:
    """按顺序执行多步骤指令。

    单步骤直接返回该步骤结果（保持原有格式）；
    多步骤依次执行，遇到失败即停止，返回合并结果。
    本批次新建的文件夹 id 会注入到后续步骤，确保引用的是刚创建的项。
    """
    if len(steps) == 1:
        return await execute(steps[0])
    results: list[dict] = []
    created_folders: dict[str, str] = {}  # 本批次新建文件夹：name -> id
    for step in steps:
        _inject_created_ids(step, created_folders)
        r = await execute(step)
        results.append(r)
        if not r["success"]:
            break  # 某步失败，后续不再执行
        # 记录 create_folder 产出的文件夹，供后续步骤引用
        if step.get("action") == "create_folder" and r.get("success"):
            data = r.get("data") or {}
            if data.get("id") and data.get("name"):
                created_folders[data["name"]] = data["id"]
    success = all(r["success"] for r in results)
    messages = [f"步骤{i + 1}：{r['message']}" for i, r in enumerate(results)]
    return {
        "action": "multi",
        "success": success,
        "message": "；".join(messages),
        "data": results,
    }


async def _handle_create_note(parsed: dict) -> dict:
    """创建笔记：用 note_generator 生成 markdown，保存到目标目录。"""
    content = parsed.get("content", "")
    if not content:
        return _result("create_note", False, "缺少笔记内容 content")
    msg_parts: list[str] = []
    # 优先用 AI 选出的目录 id
    folder_id = _id_or_none(parsed.get("target_folder_id"))
    if folder_id:
        if await crud.get_folder(folder_id) is None:
            folder_id = None
            msg_parts.append(f"目录 id 无效，已存入「未分类」")
    if folder_id is None:
        # 兜底：按用户提到的目录名查找
        target_folder = parsed.get("target_folder")
        if target_folder:
            matches = await crud.find_folders_by_name(target_folder)
            if matches:
                folder_id = matches[0]["id"]
                if len(matches) > 1:
                    msg_parts.append(f"存在多个名为「{target_folder}」的目录，已取第一个")
            else:
                uncategorized = await crud.get_default_uncategorized_folder()
                folder_id = uncategorized["id"]
                msg_parts.append(f"找不到目录「{target_folder}」，已存入「未分类」")
        else:
            uncategorized = await crud.get_default_uncategorized_folder()
            folder_id = uncategorized["id"]
    # 生成 markdown 笔记
    title, markdown = await note_generator.generate_note_with_title(content)
    file_doc = await crud.create_file(title, markdown, folder_id)
    msg = "笔记已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_note", True, msg, file_doc)


async def _handle_create_event(parsed: dict) -> dict:
    """创建日程：创建 type=event 的文件。与普通笔记统一存储，只是 type 不同。

    文件记录与普通笔记一样可编辑、移动，放入指定目录或「未分类」。
    """
    title = parsed.get("title", "")
    date = parsed.get("date", "")
    time_ = parsed.get("time", "")
    content = parsed.get("content", "")
    if not title:
        return _result("create_event", False, "缺少日程标题 title")
    if not date:
        return _result("create_event", False, "缺少日程日期 date (YYYY-MM-DD)")

    # 定位目标文件夹（与 create_note 相同逻辑）
    msg_parts: list[str] = []
    folder_id = _id_or_none(parsed.get("target_folder_id"))
    if folder_id:
        if await crud.get_folder(folder_id) is None:
            folder_id = None
            msg_parts.append("目录 id 无效，已存入「未分类」")
    if folder_id is None:
        target_folder = parsed.get("target_folder")
        if target_folder:
            matches = await crud.find_folders_by_name(target_folder)
            if matches:
                folder_id = matches[0]["id"]
                if len(matches) > 1:
                    msg_parts.append(f"存在多个名为「{target_folder}」的目录，已取第一个")
            else:
                uncategorized = await crud.get_default_uncategorized_folder()
                folder_id = uncategorized["id"]
                msg_parts.append(f"找不到目录「{target_folder}」，已存入「未分类」")
        else:
            uncategorized = await crud.get_default_uncategorized_folder()
            folder_id = uncategorized["id"]

    # 生成 markdown 内容
    if content:
        _title, markdown = await note_generator.generate_note_with_title(content)
        file_name = title
    else:
        markdown = f"# {title}\n- 日期：{date}\n" + (f"- 时间：{time_}\n" if time_ else "")
        file_name = title

    # 创建 type=event 的文件（统一存储）
    file_doc = await crud.create_file(
        name=file_name, content=markdown, parent_id=folder_id,
        file_type="event", date=date, time=time_,
    )

    msg = "日程已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_event", True, msg, file_doc)


async def _handle_append_note(parsed: dict) -> dict:
    """补充内容到已有笔记：找到笔记，用 merge_note 合并后更新 content。"""
    target_id = _id_or_none(parsed.get("target_id"))
    name = parsed.get("name")
    content = parsed.get("content", "")
    if not content:
        return _result("append_note", False, "缺少要补充的内容 content")

    # 定位笔记文件
    if target_id:
        file_doc = await crud.get_file(target_id)
        if file_doc is None:
            return _result("append_note", False, f"找不到笔记（id={target_id}）")
    else:
        if not name:
            return _result("append_note", False, "缺少要补充的笔记的 target_id 或 name")
        matches = await crud.find_files_by_name(name)
        if not matches:
            return _result("append_note", False, f"找不到笔记「{name}」")
        if len(matches) > 1:
            # 多个匹配时无法确定补充到哪条，要求用户明确
            names = "、".join(m["name"] for m in matches[:5])
            return _result("append_note", False, f"找到多条笔记：{names}，请明确要补充到哪一条")
        target_id = matches[0]["id"]
        file_doc = await crud.get_file(target_id)

    # 合并内容
    existing = file_doc.get("content", "") or ""
    merged = await note_generator.merge_note(existing, content)
    updated = await crud.update_file_content(target_id, merged)
    return _result("append_note", True, "笔记已补充", updated)


async def _handle_set_reminder(parsed: dict) -> dict:
    """为日程设置提醒（提前多少分钟 + 可选周期）。"""
    target_id = _id_or_none(parsed.get("target_id"))
    name = parsed.get("name")
    minutes = parsed.get("minutes")
    recurrence = parsed.get("recurrence", "") or ""

    if minutes is None:
        return _result("set_reminder", False, "缺少 minutes（提前多少分钟）")
    try:
        minutes = int(minutes)
    except (ValueError, TypeError):
        return _result("set_reminder", False, f"minutes 必须是数字，收到：{minutes}")
    if minutes < 0:
        return _result("set_reminder", False, "提醒分钟数不能为负")
    # minutes=0 表示取消提醒
    if minutes == 0:
        recurrence = ""

    # 校验 recurrence 值
    valid_rc = {"", "daily", "weekly", "monthly"}
    if recurrence not in valid_rc:
        return _result("set_reminder", False, f"recurrence 无效，支持：{', '.join(valid_rc)}")

    # 定位目标文件
    if target_id:
        file_doc = await crud.get_file(target_id)
        if file_doc is None:
            return _result("set_reminder", False, f"找不到文件（id={target_id}）")
    else:
        if not name:
            return _result("set_reminder", False, "缺少 target_id 或 name（要设置提醒的日程名称）")
        matches = await crud.find_files_by_name(name)
        if not matches:
            return _result("set_reminder", False, f"找不到日程「{name}」")
        if len(matches) > 1:
            return _result("set_reminder", False, f"找到多条「{name}」，请明确指定")
        target_id = matches[0]["id"]

    updated = await crud.set_reminder(target_id, minutes, recurrence)
    rc_label = {"daily": "每天", "weekly": "每周", "monthly": "每月"}.get(recurrence, "")
    label = f"已设置{'「' + rc_label + '」' if rc_label else ''}提前 {minutes} 分钟提醒"
    if minutes == 0:
        label = "已取消提醒"
    return _result("set_reminder", True, label, updated)


# device_id 需要在调用处注入，这里用一个简单的全局方式传递
_device_id: str | None = None


def set_device_id(did: str) -> None:
    global _device_id
    _device_id = did


async def _handle_save_place(parsed: dict) -> dict:
    """保存用户地点到个人地名库。"""
    name = parsed.get("name", "")
    lat = parsed.get("lat")
    lon = parsed.get("lon")
    if not name:
        return _result("save_place", False, "缺少地点名称 name")
    try:
        lat = float(lat)
        lon = float(lon)
    except (ValueError, TypeError):
        return _result("save_place", False, "坐标格式不正确")

    device_id = _device_id
    if not device_id:
        return _result("save_place", False, "缺少设备标识，无法保存地点")

    updated = await crud.add_user_place(device_id, name, lat, lon)
    if updated is None:
        return _result("save_place", False, "保存失败，用户不存在")
    return _result("save_place", True, f"已保存地点「{name}」", updated)


async def _handle_create_folder(parsed: dict) -> dict:
    """创建文件夹：优先用 parent_folder_id，否则按 parent_folder 名称查找。

    幂等：若同名同父文件夹已存在，直接复用，不重复创建。
    """
    name = parsed.get("name")
    if not name:
        return _result("create_folder", False, "缺少文件夹名称 name")
    msg_parts: list[str] = []
    parent_id = _id_or_none(parsed.get("parent_folder_id"))
    if parent_id:
        if await crud.get_folder(parent_id) is None:
            parent_id = None
            msg_parts.append(f"父目录 id 无效，已在顶级创建")
    elif parsed.get("parent_folder"):
        parent_folder = parsed.get("parent_folder")
        matches = await crud.find_folders_by_name(parent_folder)
        if matches:
            parent_id = matches[0]["id"]
            if len(matches) > 1:
                msg_parts.append(f"存在多个名为「{parent_folder}」的目录，已取第一个")
        else:
            parent_id = None
            msg_parts.append(f"找不到父目录「{parent_folder}」，已在顶级创建")
    # 幂等：同名同父已存在则复用
    existing = await crud.find_folder_exact(name, parent_id)
    if existing is not None:
        msg_parts.append(f"文件夹「{name}」已存在，直接使用")
        folder_doc = existing
    else:
        folder_doc = await crud.create_folder(name, parent_id)
    msg = "文件夹已创建" if existing is None else "文件夹已就绪"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_folder", True, msg, folder_doc)


async def _handle_rename(parsed: dict) -> dict:
    """重命名：优先用 target_id，否则按 name 在 parent 下查找。"""
    type_ = parsed.get("type")
    target_id = _id_or_none(parsed.get("target_id"))
    name = parsed.get("name") or parsed.get("old_name")
    new_name = parsed.get("new_name")
    if not new_name:
        return _result("rename", False, "缺少 new_name")
    if type_ not in ("file", "folder"):
        return _result("rename", False, "type 必须为 file 或 folder")

    msg_parts: list[str] = []

    # 优先用 id
    if target_id:
        if type_ == "folder":
            if await crud.get_folder(target_id) is None:
                return _result("rename", False, f"找不到文件夹（id={target_id}）")
            updated = await crud.update_folder_name(target_id, new_name)
        else:
            if await crud.get_file(target_id) is None:
                return _result("rename", False, f"找不到文件（id={target_id}）")
            updated = await crud.update_file_name(target_id, new_name)
        msg = "已重命名"
        if msg_parts:
            msg += "；" + "；".join(msg_parts)
        return _result("rename", True, msg, updated)

    # 兜底：按名称查找
    if not name:
        return _result("rename", False, "缺少要重命名的项的 id 或 name")
    if type_ == "folder":
        matches = await crud.find_folders_by_name(name)
        if not matches:
            return _result("rename", False, f"找不到文件夹「{name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{name}」的文件夹，已取第一个")
        updated = await crud.update_folder_name(matches[0]["id"], new_name)
    else:
        matches = await crud.find_files_by_name(name)
        if not matches:
            return _result("rename", False, f"找不到文件「{name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{name}」的文件，已取第一个")
        updated = await crud.update_file_name(matches[0]["id"], new_name)
    msg = "已重命名"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("rename", True, msg, updated)


async def _handle_delete(parsed: dict) -> dict:
    """删除：优先用 target_id，否则按 name 查找（文件夹递归）。"""
    type_ = parsed.get("type")
    target_id = _id_or_none(parsed.get("target_id"))
    name = parsed.get("name")
    if type_ not in ("file", "folder"):
        return _result("delete", False, "type 必须为 file 或 folder")

    msg_parts: list[str] = []

    # 优先用 id
    if target_id:
        if type_ == "folder":
            if await crud.get_folder(target_id) is None:
                return _result("delete", False, f"找不到文件夹（id={target_id}）")
            await crud.delete_folder(target_id)
        else:
            if await crud.get_file(target_id) is None:
                return _result("delete", False, f"找不到文件（id={target_id}）")
            await crud.delete_file(target_id)
        msg = "已删除"
        if msg_parts:
            msg += "；" + "；".join(msg_parts)
        return _result("delete", True, msg, None)

    # 兜底：按名称查找
    if not name:
        return _result("delete", False, "缺少要删除的项的 id 或 name")
    if type_ == "folder":
        matches = await crud.find_folders_by_name(name)
        if not matches:
            return _result("delete", False, f"找不到文件夹「{name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{name}」的文件夹，已取第一个")
        await crud.delete_folder(matches[0]["id"])
    else:
        matches = await crud.find_files_by_name(name)
        if not matches:
            return _result("delete", False, f"找不到文件「{name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{name}」的文件，已取第一个")
        await crud.delete_file(matches[0]["id"])
    msg = "已删除"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("delete", True, msg, None)


async def _handle_move_file(parsed: dict) -> dict:
    """移动文件：优先用 file_id / to_folder_id，否则按名称查找。"""
    file_id = _id_or_none(parsed.get("file_id"))
    to_folder_id = _id_or_none(parsed.get("to_folder_id"))
    file_name = parsed.get("file_name")
    to_folder = parsed.get("to_folder")
    msg_parts: list[str] = []

    # 定位源文件
    if file_id:
        file_doc = await crud.get_file(file_id)
        if file_doc is None:
            return _result("move_file", False, f"找不到文件（id={file_id}）")
    else:
        if not file_name:
            return _result("move_file", False, "缺少 file_id 或 file_name")
        files = await crud.find_files_by_name(file_name)
        if not files:
            return _result("move_file", False, f"找不到文件「{file_name}」")
        if len(files) > 1:
            msg_parts.append(f"存在多个文件「{file_name}」，已取第一个")
        file_id = files[0]["id"]

    # 定位目标目录
    if to_folder_id:
        if await crud.get_folder(to_folder_id) is None:
            return _result("move_file", False, f"找不到目标目录（id={to_folder_id}）")
    else:
        if not to_folder:
            return _result("move_file", False, "缺少 to_folder_id 或 to_folder")
        to_matches = await crud.find_folders_by_name(to_folder)
        if not to_matches:
            return _result("move_file", False, f"找不到目标目录「{to_folder}」")
        if len(to_matches) > 1:
            msg_parts.append(f"存在多个目标目录「{to_folder}」，已取第一个")
        to_folder_id = to_matches[0]["id"]

    updated = await crud.move_file(file_id, to_folder_id)
    msg = "文件已移动"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("move_file", True, msg, updated)


async def _handle_locate_folder(parsed: dict) -> dict:
    """定位文件夹：优先用 target_id，否则按 name 查找。data 返回 {folder_id, path}。"""
    target_id = _id_or_none(parsed.get("target_id"))
    name = parsed.get("name")
    if target_id:
        folder = await crud.get_folder(target_id)
        if folder is None:
            return _result("locate_folder", False, f"找不到文件夹（id={target_id}）")
        path = await crud.get_folder_path(target_id)
        return _result("locate_folder", True, "已定位", {"folder_id": target_id, "path": path})
    if not name:
        return _result("locate_folder", False, "缺少 target_id 或 name")
    matches = await crud.find_folders_by_name(name)
    if not matches:
        return _result("locate_folder", False, f"找不到文件夹「{name}」")
    folder = matches[0]
    path = await crud.get_folder_path(folder["id"])
    msg = "已定位"
    if len(matches) > 1:
        msg = f"存在多个名为「{name}」的文件夹，已取第一个"
    return _result("locate_folder", True, msg, {"folder_id": folder["id"], "path": path})


async def _handle_list(parsed: dict) -> dict:
    """列出内容：优先用 target_folder_id，否则按 path 名称查找；缺省返回顶级。"""
    target_folder_id = _id_or_none(parsed.get("target_folder_id"))
    path = parsed.get("path")
    if not target_folder_id and not path:
        folders = await crud.list_root_folders()
        return _result("list", True, "已列出顶级目录", {"folders": folders, "files": []})
    if target_folder_id:
        if await crud.get_folder(target_folder_id) is None:
            return _result("list", False, f"找不到目录（id={target_folder_id}）")
        children = await crud.list_children(target_folder_id)
        return _result("list", True, "已列出内容", children)
    matches = await crud.find_folders_by_name(path)
    if not matches:
        return _result("list", False, f"找不到目录「{path}」")
    children = await crud.list_children(matches[0]["id"])
    msg = "已列出内容"
    if len(matches) > 1:
        msg = f"存在多个名为「{path}」的目录，已取第一个"
    return _result("list", True, msg, children)
