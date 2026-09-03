"""根据解析后的 JSON 执行操作（PostgreSQL 后端）。

优先使用 LLM 从目录树中选出的真实 id 直接定位；
当 id 为空时，回退到按名称模糊查找（通过 SQL）。
"""

from typing import Any, Optional

from loguru import logger

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


_VALID_RECURRENCE = ("daily", "weekly", "monthly")


def _recurrence_label(recurrence: str) -> str:
    """把 recurrence 转成中文标签。"""
    labels = {"daily": "每天", "weekly": "每周", "monthly": "每月"}
    return labels.get(recurrence, recurrence)


async def _resolve_files_by_name(name: str) -> tuple[list[dict], str]:
    """按名称查找文件：SQL ILIKE 匹配 → 语义搜索兜底。"""
    if not name:
        return [], ""
    results = await db.pg_db.fetch(
        "SELECT id, name, type, date, time, created_at, updated_at FROM files WHERE name ILIKE $1 AND device_id=$2 LIMIT 5",
        f"%{name}%", db._did(),
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
    results = await db.pg_db.fetch(
        "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name ILIKE $1 AND device_id=$2 LIMIT 5",
        f"%{name}%", db._did(),
    )
    return results, "名称匹配"


async def execute(parsed: dict) -> dict:
    """根据解析结果执行操作。"""
    action = parsed.get("action", "")
    logger.info(f"[exec] action={action} params={parsed}")
    try:
        handlers = {
            "create_note": _handle_create_note,
            "create_appointment": _handle_create_appointment,
            "create_alarm": _handle_create_alarm,
            "append_note": _handle_append_note,
            "update_appointment": _handle_update_appointment,
            "update_alarm": _handle_update_alarm,
            "delete_alarm": _handle_delete_alarm,
            "delete_reminders_before": _handle_delete_reminders_before,
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
        "create_appointment": ("target_folder_id", "target_folder"),
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
    """执行安全的 SQL SELECT 查询（带设备隔离）。"""
    sql = parsed.get("sql", "")
    if not sql:
        return _result("run_query", False, "缺少 SQL 查询语句")
    try:
        rows = await db.run_scoped_query(sql)
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


async def _handle_create_appointment(parsed: dict) -> dict:
    title = parsed.get("title", "") or parsed.get("name", "")
    date = parsed.get("date", "")
    time_ = parsed.get("time", "")
    content = parsed.get("content", "")
    if not title:
        return _result("create_appointment", False, "缺少安排标题")
    if not date:
        return _result("create_appointment", False, "缺少安排日期 date (YYYY-MM-DD)")
    # 安排为一次性日程，不归属文件夹
    doc = await db.create_file(title, content, None, file_type="appointment", date=date, time=time_)
    await _store_embedding(doc["id"], title, content)
    return _result("create_appointment", True, "安排已创建", doc)


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


async def _handle_create_alarm(parsed: dict) -> dict:
    name = parsed.get("name", "") or parsed.get("title", "")
    time_ = str(parsed.get("time") or "").strip()
    recurrence = str(parsed.get("recurrence") or "daily").strip() or "daily"
    content = parsed.get("content", "")
    if not name:
        return _result("create_alarm", False, "缺少闹钟名称")
    if recurrence not in _VALID_RECURRENCE:
        return _result("create_alarm", False, f"recurrence 无效：{recurrence}")
    if not time_:
        return _result("create_alarm", False, "缺少触发时间 time (HH:MM)")
    # 闹钟为周期性提醒，不归属文件夹
    doc = await db.create_file(
        name, content, None, file_type="alarm", time=time_, recurrence=recurrence,
    )
    await _store_embedding(doc["id"], name, content)
    rc_label = _recurrence_label(recurrence)
    msg = f"闹钟已创建（{rc_label} {time_}）"
    return _result("create_alarm", True, msg, doc)


async def _handle_delete_alarm(parsed: dict) -> dict:
    """删除闹钟。"""
    file_id, doc, err = await _resolve_file(parsed, "闹钟")
    if err:
        return _result("delete_alarm", False, err)
    ok = await db.delete_file(file_id)
    if not ok:
        return _result("delete_alarm", False, "删除闹钟失败")
    return _result("delete_alarm", True, "已删除闹钟", None)


async def _handle_delete_reminders_before(parsed: dict) -> dict:
    """批量删除某日期之前的所有安排（一次性提醒）。"""
    date_str = str(parsed.get("date") or "").strip()
    if not date_str:
        return _result("delete_reminders_before", False, "缺少日期 date (YYYY-MM-DD)")
    try:
        count = await db.delete_reminders_before(date_str)
    except ValueError as e:
        return _result("delete_reminders_before", False, str(e))
    return _result("delete_reminders_before", True, f"已删除 {count} 条安排", {"deleted": count})


async def _handle_update_appointment(parsed: dict) -> dict:
    """更新安排（一次性）的标题/日期/时间/内容。"""
    file_id, doc, err = await _resolve_file(parsed, "安排")
    if err:
        return _result("update_appointment", False, err)

    name = str(parsed.get("name") or "").strip() or None
    date = str(parsed.get("date") or "").strip() or None
    time = str(parsed.get("time") or "").strip() or None
    content = parsed.get("content")

    updated = await db.update_appointment(file_id, name=name, date=date, time=time, content=content)
    if updated is None:
        return _result("update_appointment", False, "安排不存在或更新失败")

    parts: list[str] = []
    if name:
        parts.append(f"标题 {name}")
    if date:
        parts.append(f"日期 {date}")
    if time:
        parts.append(f"时间 {time}")
    label = "已更新安排：" + "，".join(parts) if parts else "安排已更新"
    return _result("update_appointment", True, label, updated)


async def _handle_update_alarm(parsed: dict) -> dict:
    """更新闹钟（周期性）的标题/时间/周期/内容。"""
    file_id, doc, err = await _resolve_file(parsed, "闹钟")
    if err:
        return _result("update_alarm", False, err)

    name = str(parsed.get("name") or "").strip() or None
    time = str(parsed.get("time") or "").strip() or None
    recurrence = str(parsed.get("recurrence") or "").strip() or None
    if recurrence and recurrence not in _VALID_RECURRENCE:
        return _result("update_alarm", False, f"recurrence 无效：{recurrence}")
    content = parsed.get("content")

    updated = await db.update_alarm(
        file_id, name=name, time=time, recurrence=recurrence,
        content=content,
    )
    if updated is None:
        return _result("update_alarm", False, "闹钟不存在或更新失败")

    parts: list[str] = []
    if name:
        parts.append(f"标题 {name}")
    if time:
        parts.append(f"时间 {time}")
    if recurrence:
        parts.append(f"周期 {_recurrence_label(recurrence)}")
    label = "已更新闹钟：" + "，".join(parts) if parts else "闹钟已更新"
    return _result("update_alarm", True, label, updated)


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
