"""根据解析后的 JSON 执行操作。

所有异常/未找到场景返回 success=false 和可读 message，不抛 500。
对于重名（多个匹配）：暂取第一个，并在 message 中提示存在多个匹配。
"""

from typing import Any, Optional, Tuple

from .. import crud
from . import note_generator


def _result(action: str, success: bool, message: str, data: Any = None) -> dict:
    """构造统一结果对象。"""
    return {"action": action, "success": success, "message": message, "data": data}


async def _resolve_parent(parent_folder: Optional[str]) -> Tuple[Optional[str], str, str]:
    """解析父目录（用于 rename/delete 定位）。

    Returns:
        (parent_id, message, error)
        - parent_folder 未提供 -> (None, "", "")
        - 提供且找到 -> (id, 多匹配提示, "")
        - 提供但未找到 -> (None, "", "找不到目录 X")
    """
    if not parent_folder:
        return None, "", ""
    matches = await crud.find_folders_by_name(parent_folder)
    if not matches:
        return None, "", f"找不到目录「{parent_folder}」"
    msg = f"存在多个名为「{parent_folder}」的目录，已取第一个" if len(matches) > 1 else ""
    return matches[0]["id"], msg, ""


async def execute(parsed: dict) -> dict:
    """根据解析结果执行操作，返回统一结果对象。"""
    action = parsed.get("action", "")
    try:
        if action == "create_note":
            return await _handle_create_note(parsed)
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


async def _handle_create_note(parsed: dict) -> dict:
    """创建笔记：用 note_generator 生成 markdown，保存到目标目录。"""
    content = parsed.get("content", "")
    if not content:
        return _result("create_note", False, "缺少笔记内容 content")
    target_folder = parsed.get("target_folder")
    msg_parts: list[str] = []
    if target_folder:
        matches = await crud.find_folders_by_name(target_folder)
        if matches:
            parent_id = matches[0]["id"]
            if len(matches) > 1:
                msg_parts.append(f"存在多个名为「{target_folder}」的目录，已取第一个")
        else:
            uncategorized = await crud.get_default_uncategorized_folder()
            parent_id = uncategorized["id"]
            msg_parts.append(f"找不到目录「{target_folder}」，已存入「未分类」")
    else:
        uncategorized = await crud.get_default_uncategorized_folder()
        parent_id = uncategorized["id"]
    # 生成 markdown 笔记
    title, markdown = await note_generator.generate_note_with_title(content)
    file_doc = await crud.create_file(title, markdown, parent_id)
    msg = "笔记已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_note", True, msg, file_doc)


async def _handle_create_folder(parsed: dict) -> dict:
    """创建文件夹：parent_folder 找不到则顶级。"""
    name = parsed.get("name")
    if not name:
        return _result("create_folder", False, "缺少文件夹名称 name")
    parent_folder = parsed.get("parent_folder")
    msg_parts: list[str] = []
    if parent_folder:
        matches = await crud.find_folders_by_name(parent_folder)
        if matches:
            parent_id = matches[0]["id"]
            if len(matches) > 1:
                msg_parts.append(f"存在多个名为「{parent_folder}」的目录，已取第一个")
        else:
            parent_id = None
            msg_parts.append(f"找不到父目录「{parent_folder}」，已在顶级创建")
    else:
        parent_id = None
    folder_doc = await crud.create_folder(name, parent_id)
    msg = "文件夹已创建"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("create_folder", True, msg, folder_doc)


async def _handle_rename(parsed: dict) -> dict:
    """重命名：在 parent_folder 下按 type 和 old_name 找到目标。"""
    type_ = parsed.get("type")
    old_name = parsed.get("old_name")
    new_name = parsed.get("new_name")
    parent_folder = parsed.get("parent_folder")
    if not old_name or not new_name:
        return _result("rename", False, "缺少 old_name 或 new_name")
    if type_ not in ("file", "folder"):
        return _result("rename", False, "type 必须为 file 或 folder")
    parent_id, pmsg, perr = await _resolve_parent(parent_folder)
    if perr:
        return _result("rename", False, perr)
    msg_parts = [p for p in [pmsg] if p]
    if type_ == "folder":
        matches = await crud.find_folders_by_name(old_name, parent_id)
        if not matches:
            return _result("rename", False, f"找不到文件夹「{old_name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{old_name}」的文件夹，已取第一个")
        updated = await crud.update_folder_name(matches[0]["id"], new_name)
    else:
        matches = await crud.find_files_by_name(old_name, parent_id)
        if not matches:
            return _result("rename", False, f"找不到文件「{old_name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{old_name}」的文件，已取第一个")
        updated = await crud.update_file_name(matches[0]["id"], new_name)
    msg = "已重命名"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("rename", True, msg, updated)


async def _handle_delete(parsed: dict) -> dict:
    """删除：在 parent_folder 下按 type 和 name 找到目标（文件夹递归）。"""
    type_ = parsed.get("type")
    name = parsed.get("name")
    parent_folder = parsed.get("parent_folder")
    if not name:
        return _result("delete", False, "缺少名称 name")
    if type_ not in ("file", "folder"):
        return _result("delete", False, "type 必须为 file 或 folder")
    parent_id, pmsg, perr = await _resolve_parent(parent_folder)
    if perr:
        return _result("delete", False, perr)
    msg_parts = [p for p in [pmsg] if p]
    if type_ == "folder":
        matches = await crud.find_folders_by_name(name, parent_id)
        if not matches:
            return _result("delete", False, f"找不到文件夹「{name}」")
        if len(matches) > 1:
            msg_parts.append(f"存在多个名为「{name}」的文件夹，已取第一个")
        await crud.delete_folder(matches[0]["id"])
    else:
        matches = await crud.find_files_by_name(name, parent_id)
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
    """移动文件：在 from_folder 下找 file_name，更新 parent_id 为 to_folder 的 id。"""
    file_name = parsed.get("file_name")
    from_folder = parsed.get("from_folder")
    to_folder = parsed.get("to_folder")
    if not file_name or not from_folder or not to_folder:
        return _result("move_file", False, "缺少 file_name/from_folder/to_folder")
    from_matches = await crud.find_folders_by_name(from_folder)
    if not from_matches:
        return _result("move_file", False, f"找不到源目录「{from_folder}」")
    to_matches = await crud.find_folders_by_name(to_folder)
    if not to_matches:
        return _result("move_file", False, f"找不到目标目录「{to_folder}」")
    files = await crud.find_files_by_name(file_name, from_matches[0]["id"])
    if not files:
        return _result(
            "move_file", False, f"在目录「{from_folder}」中找不到文件「{file_name}」"
        )
    msg_parts: list[str] = []
    if len(from_matches) > 1:
        msg_parts.append(f"存在多个源目录「{from_folder}」，已取第一个")
    if len(to_matches) > 1:
        msg_parts.append(f"存在多个目标目录「{to_folder}」，已取第一个")
    if len(files) > 1:
        msg_parts.append(f"存在多个文件「{file_name}」，已取第一个")
    updated = await crud.move_file(files[0]["id"], to_matches[0]["id"])
    msg = "文件已移动"
    if msg_parts:
        msg += "；" + "；".join(msg_parts)
    return _result("move_file", True, msg, updated)


async def _handle_locate_folder(parsed: dict) -> dict:
    """定位文件夹：按 folder_name 找，data 返回 {folder_id, path}。"""
    folder_name = parsed.get("folder_name")
    if not folder_name:
        return _result("locate_folder", False, "缺少 folder_name")
    matches = await crud.find_folders_by_name(folder_name)
    if not matches:
        return _result("locate_folder", False, f"找不到文件夹「{folder_name}」")
    folder = matches[0]
    path = await crud.get_folder_path(folder["id"])
    msg = "已定位"
    if len(matches) > 1:
        msg = f"存在多个名为「{folder_name}」的文件夹，已取第一个"
    return _result("locate_folder", True, msg, {"folder_id": folder["id"], "path": path})


async def _handle_list(parsed: dict) -> dict:
    """列出内容：path 缺省返回顶级文件夹列表；否则返回该文件夹的子项。"""
    path = parsed.get("path")
    if not path:
        folders = await crud.list_root_folders()
        return _result("list", True, "已列出顶级目录", {"folders": folders, "files": []})
    matches = await crud.find_folders_by_name(path)
    if not matches:
        return _result("list", False, f"找不到目录「{path}」")
    folder = matches[0]
    children = await crud.list_children(folder["id"])
    msg = "已列出内容"
    if len(matches) > 1:
        msg = f"存在多个名为「{path}」的目录，已取第一个"
    return _result("list", True, msg, children)
