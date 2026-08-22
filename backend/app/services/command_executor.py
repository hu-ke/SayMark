"""根据解析后的 JSON 执行操作（PostgreSQL 后端）。

优先使用 LLM 从目录树中选出的真实 id 直接定位；
当 id 为空时，回退到按名称模糊查找（通过 SQL）。
"""

from typing import Any, Optional

from .. import pg_ops as db
from . import note_generator, qwen


async def _store_embedding(file_id: int, title: str, content: str) -> None:
    """为文件生成并存储 embedding 向量。"""
    try:
        text = f"{title}\n{content[:500]}"
        vec = await qwen.embed(text)
        await db.update_file_embedding(file_id, vec)
    except Exception:
        pass


def _result(action: str, success: bool, message: str, data: Any = None) -> dict:
    return {"action": action, "success": success, "message": message, "data": data}


def _int_id(value: Any) -> int | None:
    """安全地将值转为 int id，失败返回 None。"""
    if value is None:
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        return None


async def _resolve_files_by_name(name: str) -> tuple[list[dict], str]:
    """按名称查找文件：SQL ILIKE 匹配 → 语义搜索兜底。"""
    if not name:
        return [], ""
    results = await db.run_safe_query(
        f"SELECT id, name, type, date, time, created_at, updated_at FROM files WHERE name ILIKE '%{name}%' LIMIT 5"
    )
    if results:
        return results, "名称匹配"
    semantic = await db.search_files_semantic(name, top_k=5)
    if semantic:
        return semantic, "语义匹配"
    return [], ""


async def _resolve_folders_by_name(name: str) -> tuple[list[dict], str]:
    """按名称查找文件夹（SQL ILIKE）。"""
    if not name:
        return [], ""
    results = await db.run_safe_query(
        f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name ILIKE '%{name}%' LIMIT 5"
    )
    return results, "名称匹配"


async def execute(parsed: dict) -> dict:
    """根据解析结果执行操作。"""
    action = parsed.get("action", "")
    try:
        handlers = {
            "create_note": _handle_create_note,
            "create_event": _handle_create_event,
            "append_note": _handle_append_note,
            "set_reminder": _handle_set_reminder,
            "cancel_reminder": _handle_cancel_reminder,
            "update_schedule": _handle_update_schedule,
            "save_place": _handle_save_place,
            "create_folder": _handle_create_folder,
            "rename": _handle_rename,
            "delete": _handle_delete,
            "move_file": _handle_move_file,
            "locate_folder": _handle_locate_folder,
            "list": _handle_list,
            "run_query": _handle_run_query,
        }
        handler = handlers.get(action)
        if handler is None:
            return _result(action or "unknown", False, f"不支持的操作: {action}")
        return await handler(parsed)
    except Exception as e:
        return _result(action, False, f"执行失败: {e}")


async def execute_steps(steps: list[dict]) -> dict:
    """按顺序执行多步骤指令。"""
    if len(steps) == 1:
        return await execute(steps[0])
    results: list[dict] = []
    created_folders: dict[str, int] = {}
    for step in steps:
        _inject_created_ids(step, created_folders)
        r = await execute(step)
        results.append(r)
        if not r["success"]:
            break
        if step.get("action") == "create_folder" and r.get("success"):
            data = r.get("data") or {}
            fid = _int_id(data.get("id"))
            name = data.get("name", "")
            if fid and name:
                created_folders[name] = fid
    success = all(r["success"] for r in results)
    messages = [f"步骤{i + 1}：{r['message']}" for i, r in enumerate(results)]
    return {"action": "multi", "success": success, "message": "；".join(messages), "data": results}


def _inject_created_ids(step: dict, created: dict[str, int]) -> None:
    """将本批次新建的文件夹 id 注入后续步骤。"""
    if not created:
        return
    key_map = {
        "move_file": ("to_folder_id", "to_folder"),
        "create_note": ("target_folder_id", "target_folder"),
        "create_event": ("target_folder_id", "target_folder"),
        "create_folder": ("parent_folder_id", "parent_folder"),
        "list": ("target_folder_id", "path"),
    }
    pair = key_map.get(step.get("action"))
    if pair:
        id_key, name_key = pair
        if not step.get(id_key):
            fid = created.get(step.get(name_key, ""))
            if fid:
                step[id_key] = fid


async def _resolve_target_folder(parsed: dict) -> tuple[int, list[str]]:
    """解析目标文件夹 id。返回 (folder_id, msg_parts)。"""
    msg: list[str] = []
    folder_id = _int_id(parsed.get("target_folder_id"))
    if folder_id:
        if await db.get_folder(folder_id) is None:
            folder_id = None
            msg.append("目录 id 无效，已存入「未分类」")
    if folder_id is None:
        target_name = parsed.get("target_folder")
        if target_name:
            matches, _ = await _resolve_folders_by_name(target_name)
            if matches:
                folder_id = _int_id(matches[0]["id"])
                if len(matches) > 1:
                    msg.append(f"存在多个名为「{target_name}」的目录，已取第一个")
            else:
                f = await db.get_default_uncategorized_folder()
                folder_id = _int_id(f["id"])
                msg.append(f"找不到目录「{target_name}」，已存入「未分类」")
        else:
            f = await db.get_default_uncategorized_folder()
            folder_id = _int_id(f["id"])
    return folder_id, msg


async def _resolve_file(parsed: dict, action: str) -> tuple[int | None, dict | None, str]:
    """解析目标文件。返回 (file_id, file_doc, error_msg)。error_msg 非空表示失败。"""
    file_id = _int_id(parsed.get("target_id"))
    if file_id:
        doc = await db.get_file(file_id)
        if doc is None:
            return None, None, f"找不到{action}目标（id={file_id}）"
        return file_id, doc, ""

    name = parsed.get("name")
    if not name:
        return None, None, f"缺少 target_id 或 name"
    matches, match_type = await _resolve_files_by_name(name)
    if not matches:
        return None, None, f"找不到「{name}」"
    if len(matches) > 1:
        names = "、".join(m["name"] for m in matches[:5])
        label = f"（{match_type}）" if match_type == "语义匹配" else ""
        return None, None, f"找到多条匹配{label}：{names}，请明确指定"
    return _int_id(matches[0]["id"]), await db.get_file(_int_id(matches[0]["id"])), ""


# ----------------------------- Handlers -----------------------------


async def _handle_run_query(parsed: dict) -> dict:
    """执行安全的 SQL SELECT 查询。"""
    sql = parsed.get("sql", "")
    if not sql:
        return _result("run_query", False, "缺少 SQL 查询语句")
    try:
        rows = await db.run_safe_query(sql)
        return _result("run_query", True, f"查询返回 {len(rows)} 条结果", {"rows": rows, "count": len(rows)})
    except ValueError as e:
        return _result("run_query", False, str(e))


async def _handle_create_note(parsed: dict) -> dict:
    content = parsed.get("content", "")
    if not content:
        return _result("create_note", False, "缺少笔记内容 content")
    folder_id, msg_parts = await _resolve_target_folder(parsed)
    title, markdown = await note_generator.generate_note_with_title(content)
    doc = await db.create_file(title, markdown, folder_id)
    await _store_embedding(doc["id"], title, markdown)
    msg = "笔记已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_note", True, msg, doc)


async def _handle_create_event(parsed: dict) -> dict:
    title = parsed.get("title", "")
    date = parsed.get("date", "")
    time_ = parsed.get("time", "")
    content = parsed.get("content", "")
    if not title:
        return _result("create_event", False, "缺少日程标题 title")
    if not date:
        return _result("create_event", False, "缺少日程日期 date (YYYY-MM-DD)")
    folder_id, msg_parts = await _resolve_target_folder(parsed)
    # 详情页已展示日期/时间，content 只保存正文，不重复拼日期/时间
    markdown = content
    doc = await db.create_file(title, markdown, folder_id, file_type="event", date=date, time=time_)
    await _store_embedding(doc["id"], title, markdown)
    msg = "日程已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_event", True, msg, doc)


async def _handle_append_note(parsed: dict) -> dict:
    content = parsed.get("content", "")
    if not content:
        return _result("append_note", False, "缺少要补充的内容 content")
    file_id, doc, err = await _resolve_file(parsed, "笔记")
    if err:
        return _result("append_note", False, err)
    existing = doc.get("content", "") or ""
    merged = await note_generator.merge_note(existing, content)
    updated = await db.update_file_content(file_id, merged)
    await _store_embedding(file_id, doc.get("name", ""), merged)
    return _result("append_note", True, "笔记已补充", updated)


async def _handle_set_reminder(parsed: dict) -> dict:
    minutes = parsed.get("minutes")
    if minutes is None:
        return _result("set_reminder", False, "缺少 minutes（提前多少分钟）")
    try:
        minutes = int(minutes)
    except (ValueError, TypeError):
        return _result("set_reminder", False, f"minutes 必须是数字，收到：{minutes}")
    if minutes < 0:
        return _result("set_reminder", False, "提醒分钟数不能为负")
    recurrence = str(parsed.get("recurrence") or "")
    end_date = str(parsed.get("recurrence_end_date") or "")
    if recurrence not in ("", "daily", "weekly", "monthly"):
        return _result("set_reminder", False, f"recurrence 无效：{recurrence}")
    if minutes == 0:
        recurrence = ""
    file_id, doc, err = await _resolve_file(parsed, "日程")
    if err:
        return _result("set_reminder", False, err)
    updated = await db.set_reminder(file_id, minutes, recurrence, end_date)
    rc_label = {"daily": "每天", "weekly": "每周", "monthly": "每月"}.get(recurrence, "")
    if minutes == 0:
        label = "已设置到点提醒"
    else:
        label = f"已设置{'「' + rc_label + '」' if rc_label else ''}提前 {minutes} 分钟提醒"
    if end_date:
        label += f"（至{end_date}）"
    return _result("set_reminder", True, label, updated)


async def _handle_cancel_reminder(parsed: dict) -> dict:
    """取消日程提醒。"""
    file_id, doc, err = await _resolve_file(parsed, "日程")
    if err:
        return _result("cancel_reminder", False, err)
    updated = await db.clear_reminder(file_id)
    if updated is None:
        return _result("cancel_reminder", False, "取消提醒失败")
    return _result("cancel_reminder", True, "已取消提醒", updated)


_VALID_REPEAT_UNITS = {"seconds", "minutes", "hours", "days"}
_REPEAT_UNIT_LABELS = {"seconds": "秒", "minutes": "分钟", "hours": "小时", "days": "天"}


async def _handle_update_schedule(parsed: dict) -> dict:
    """更新日程属性（日期/时间/提醒/重复）。用于详情页内语音调整日程。"""
    file_id, doc, err = await _resolve_file(parsed, "日程")
    if err:
        return _result("update_schedule", False, err)

    def _opt_int(key: str) -> int | None:
        v = parsed.get(key)
        if v is None or v == "":
            return None
        try:
            return int(v)
        except (ValueError, TypeError):
            return None

    date = str(parsed.get("date") or "").strip() or None
    time = str(parsed.get("time") or "").strip() or None
    reminder_minutes = _opt_int("reminder_minutes")

    repeat_enabled = parsed.get("repeat_enabled")
    if repeat_enabled is not None and not isinstance(repeat_enabled, bool):
        repeat_enabled = str(repeat_enabled).lower() in ("true", "1", "yes")

    repeat_unit = str(parsed.get("repeat_unit") or "").strip() or None
    repeat_value = _opt_int("repeat_value")

    if repeat_unit and repeat_unit not in _VALID_REPEAT_UNITS:
        return _result("update_schedule", False, f"repeat_unit 无效：{repeat_unit}")

    updated = await db.update_file_schedule(
        file_id,
        date=date,
        time=time,
        reminder_minutes=reminder_minutes,
        repeat_enabled=repeat_enabled,
        repeat_unit=repeat_unit,
        repeat_value=repeat_value,
    )
    if updated is None:
        return _result("update_schedule", False, "日程不存在或更新失败")

    parts: list[str] = []
    if date:
        parts.append(f"日期 {date}")
    if time:
        parts.append(f"时间 {time}")
    if reminder_minutes is not None:
        parts.append("取消提醒" if reminder_minutes <= 0 else f"提前 {reminder_minutes} 分钟提醒")
    if repeat_enabled is not None:
        if repeat_enabled and repeat_unit and repeat_value:
            unit_label = _REPEAT_UNIT_LABELS.get(repeat_unit, repeat_unit)
            parts.append(f"每 {repeat_value} {unit_label}重复")
        elif not repeat_enabled:
            parts.append("取消重复")
    label = "已更新日程：" + "，".join(parts) if parts else "日程已更新"
    return _result("update_schedule", True, label, updated)


_device_id: str | None = None


def set_device_id(did: str) -> None:
    global _device_id
    _device_id = did


async def _handle_save_place(parsed: dict) -> dict:
    name = parsed.get("name", "")
    try:
        lat = float(parsed.get("lat", 0))
        lon = float(parsed.get("lon", 0))
    except (ValueError, TypeError):
        return _result("save_place", False, "坐标格式不正确")
    if not name:
        return _result("save_place", False, "缺少地点名称 name")
    if not _device_id:
        return _result("save_place", False, "缺少设备标识")
    updated = await db.add_user_place(_device_id, name, lat, lon)
    if updated is None:
        return _result("save_place", False, "保存失败，用户不存在")
    return _result("save_place", True, f"已保存地点「{name}」", updated)


async def _handle_create_folder(parsed: dict) -> dict:
    name = parsed.get("name")
    if not name:
        return _result("create_folder", False, "缺少文件夹名称 name")
    msg_parts: list[str] = []
    parent_id = _int_id(parsed.get("parent_folder_id"))
    if parent_id and await db.get_folder(parent_id) is None:
        parent_id = None
        msg_parts.append("父目录 id 无效，已在顶级创建")
    elif parent_id is None and parsed.get("parent_folder"):
        matches, _ = await _resolve_folders_by_name(parsed["parent_folder"])
        if matches:
            parent_id = _int_id(matches[0]["id"])
        else:
            msg_parts.append(f"找不到父目录「{parsed['parent_folder']}」，已在顶级创建")
    doc = await db.create_folder(name, parent_id)
    msg = "文件夹已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_folder", True, msg, doc)


async def _handle_rename(parsed: dict) -> dict:
    type_ = parsed.get("type")
    new_name = parsed.get("new_name")
    if not new_name:
        return _result("rename", False, "缺少 new_name")
    if type_ not in ("file", "folder"):
        return _result("rename", False, "type 必须为 file 或 folder")

    target_id = _int_id(parsed.get("target_id"))
    if target_id:
        if type_ == "folder":
            updated = await db.update_folder_name(target_id, new_name)
        else:
            updated = await db.update_file_name(target_id, new_name)
        if updated is None:
            return _result("rename", False, f"找不到{'文件夹' if type_ == 'folder' else '文件'}（id={target_id}）")
        return _result("rename", True, "已重命名", updated)

    name = parsed.get("name") or parsed.get("old_name")
    if not name:
        return _result("rename", False, "缺少要重命名的项的 id 或 name")
    if type_ == "folder":
        matches, _ = await _resolve_folders_by_name(name)
    else:
        matches, _ = await _resolve_files_by_name(name)
    if not matches:
        return _result("rename", False, f"找不到{'文件夹' if type_ == 'folder' else '文件'}「{name}」")
    fid = _int_id(matches[0]["id"])
    if type_ == "folder":
        updated = await db.update_folder_name(fid, new_name)
    else:
        updated = await db.update_file_name(fid, new_name)
    return _result("rename", True, "已重命名", updated)


async def _handle_delete(parsed: dict) -> dict:
    type_ = parsed.get("type")
    if type_ not in ("file", "folder"):
        return _result("delete", False, "type 必须为 file 或 folder")

    target_id = _int_id(parsed.get("target_id"))
    if target_id:
        if type_ == "folder":
            ok = await db.delete_folder(target_id)
        else:
            ok = await db.delete_file(target_id)
        if not ok:
            return _result("delete", False, f"找不到{'文件夹' if type_ == 'folder' else '文件'}（id={target_id}）")
        return _result("delete", True, "已删除")

    name = parsed.get("name")
    if not name:
        return _result("delete", False, "缺少要删除的项的 id 或 name")
    if type_ == "folder":
        matches, _ = await _resolve_folders_by_name(name)
    else:
        matches, _ = await _resolve_files_by_name(name)
    if not matches:
        return _result("delete", False, f"找不到{'文件夹' if type_ == 'folder' else '文件'}「{name}」")
    fid = _int_id(matches[0]["id"])
    if type_ == "folder":
        await db.delete_folder(fid)
    else:
        await db.delete_file(fid)
    return _result("delete", True, "已删除")


async def _handle_move_file(parsed: dict) -> dict:
    file_id = _int_id(parsed.get("file_id"))
    if file_id is None:
        file_name = parsed.get("file_name")
        if not file_name:
            return _result("move_file", False, "缺少 file_id 或 file_name")
        matches, _ = await _resolve_files_by_name(file_name)
        if not matches:
            return _result("move_file", False, f"找不到文件「{file_name}」")
        file_id = _int_id(matches[0]["id"])

    to_folder_id = _int_id(parsed.get("to_folder_id"))
    if to_folder_id is None:
        to_folder = parsed.get("to_folder", "")
        if not to_folder:
            return _result("move_file", False, "缺少 to_folder_id 或 to_folder")
        matches, _ = await _resolve_folders_by_name(to_folder)
        if not matches:
            return _result("move_file", False, f"找不到目标目录「{to_folder}」")
        to_folder_id = _int_id(matches[0]["id"])

    updated = await db.move_file(file_id, to_folder_id)
    if updated is None:
        return _result("move_file", False, f"移动失败")
    return _result("move_file", True, "文件已移动", updated)


async def _handle_locate_folder(parsed: dict) -> dict:
    target_id = _int_id(parsed.get("target_id"))
    if target_id:
        folder = await db.get_folder(target_id)
        if folder is None:
            return _result("locate_folder", False, f"找不到文件夹（id={target_id}）")
        path = await db.get_folder_path(target_id)
        return _result("locate_folder", True, "已定位", {"folder_id": target_id, "path": path})
    name = parsed.get("name")
    if not name:
        return _result("locate_folder", False, "缺少 target_id 或 name")
    matches, _ = await _resolve_folders_by_name(name)
    if not matches:
        return _result("locate_folder", False, f"找不到文件夹「{name}」")
    fid = _int_id(matches[0]["id"])
    path = await db.get_folder_path(fid)
    return _result("locate_folder", True, "已定位", {"folder_id": fid, "path": path})


async def _handle_list(parsed: dict) -> dict:
    target_id = _int_id(parsed.get("target_folder_id"))
    path = parsed.get("path")
    if not target_id and not path:
        folders = await db.list_root_folders()
        return _result("list", True, "已列出顶级目录", {"folders": folders, "files": []})
    if target_id:
        if await db.get_folder(target_id) is None:
            return _result("list", False, f"找不到目录（id={target_id}）")
        children = await db.list_children(target_id)
        return _result("list", True, "已列出内容", children)
    matches, _ = await _resolve_folders_by_name(path)
    if not matches:
        return _result("list", False, f"找不到目录「{path}」")
    children = await db.list_children(_int_id(matches[0]["id"]))
    return _result("list", True, "已列出内容", children)
