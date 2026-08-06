"""数据访问层（folders / files 的 CRUD）。

全部 async，使用 motor。ID 在 API 层用字符串，内部转 ObjectId。
"""

from datetime import datetime, timezone
from typing import Optional

from bson import ObjectId
from bson.errors import InvalidId

from .database import get_db

# "未分类"顶级目录名
UNCATEGORIZED_FOLDER_NAME = "未分类"


# ----------------------------- 工具函数 -----------------------------


def _to_objectid(id_str: str) -> ObjectId:
    """字符串转 ObjectId，转换失败抛 ValueError。"""
    if not ObjectId.is_valid(id_str):
        raise ValueError(f"无效的 ID: {id_str}")
    return ObjectId(id_str)


def _dt_iso(value) -> str:
    """把 datetime 转为 ISO 字符串；其他类型原样转字符串。"""
    if isinstance(value, datetime):
        return value.isoformat()
    if value is None:
        return ""
    return str(value)


def _serialize_folder(doc: Optional[dict]) -> Optional[dict]:
    """序列化文件夹文档为响应格式（None 透传）。"""
    if doc is None:
        return None
    return {
        "id": str(doc["_id"]),
        "name": doc["name"],
        "parent_id": str(doc["parent_id"]) if doc.get("parent_id") is not None else None,
        "created_at": _dt_iso(doc.get("created_at")),
        "updated_at": _dt_iso(doc.get("updated_at")),
    }


def _serialize_file(doc: Optional[dict], include_content: bool = True) -> Optional[dict]:
    """序列化文件文档为响应格式（None 透传）。"""
    if doc is None:
        return None
    result = {
        "id": str(doc["_id"]),
        "name": doc["name"],
        "parent_id": str(doc["parent_id"]) if doc.get("parent_id") is not None else None,
        "created_at": _dt_iso(doc.get("created_at")),
        "updated_at": _dt_iso(doc.get("updated_at")),
    }
    if include_content:
        result["content"] = doc.get("content", "")
    return result


def _now() -> datetime:
    """当前 UTC 时间。"""
    return datetime.now(timezone.utc)


# ----------------------------- 查询 -----------------------------


async def list_root_folders() -> list[dict]:
    """列出顶级文件夹（parent_id 为 null）。"""
    db = get_db()
    docs = await db.folders.find({"parent_id": None}).sort("created_at", 1).to_list(None)
    return [_serialize_folder(d) for d in docs]


async def list_children(folder_id: str) -> dict:
    """列出某文件夹的子文件夹与子文件。"""
    db = get_db()
    oid = _to_objectid(folder_id)
    folders = await db.folders.find({"parent_id": oid}).sort("created_at", 1).to_list(None)
    files = await db.files.find({"parent_id": oid}).sort("created_at", 1).to_list(None)
    return {
        "folders": [_serialize_folder(d) for d in folders],
        "files": [_serialize_file(d, include_content=False) for d in files],
    }


async def get_folder(folder_id: str) -> Optional[dict]:
    """按 ID 获取文件夹，找不到返回 None。"""
    db = get_db()
    doc = await db.folders.find_one({"_id": _to_objectid(folder_id)})
    return _serialize_folder(doc)


async def get_file(file_id: str) -> Optional[dict]:
    """按 ID 获取文件（含 content），找不到返回 None。"""
    db = get_db()
    doc = await db.files.find_one({"_id": _to_objectid(file_id)})
    return _serialize_file(doc, include_content=True)


# ----------------------------- 创建 -----------------------------


async def create_folder(name: str, parent_id: Optional[str] = None) -> dict:
    """创建文件夹。parent_id 为 None 表示顶级目录。"""
    db = get_db()
    now = _now()
    parent_oid = _to_objectid(parent_id) if parent_id else None
    result = await db.folders.insert_one(
        {
            "name": name,
            "parent_id": parent_oid,
            "created_at": now,
            "updated_at": now,
        }
    )
    doc = await db.folders.find_one({"_id": result.inserted_id})
    return _serialize_folder(doc)


async def create_file(name: str, content: str, parent_id: str) -> dict:
    """创建文件。parent_id 必须提供。"""
    db = get_db()
    now = _now()
    parent_oid = _to_objectid(parent_id)
    result = await db.files.insert_one(
        {
            "name": name,
            "content": content,
            "parent_id": parent_oid,
            "created_at": now,
            "updated_at": now,
        }
    )
    doc = await db.files.find_one({"_id": result.inserted_id})
    return _serialize_file(doc, include_content=True)


# ----------------------------- 更新 -----------------------------


async def update_folder_name(folder_id: str, name: str) -> Optional[dict]:
    """重命名文件夹，返回更新后的文档，找不到返回 None。"""
    db = get_db()
    res = await db.folders.update_one(
        {"_id": _to_objectid(folder_id)},
        {"$set": {"name": name, "updated_at": _now()}},
    )
    if res.matched_count == 0:
        return None
    doc = await db.folders.find_one({"_id": _to_objectid(folder_id)})
    return _serialize_folder(doc)


async def update_file_name(file_id: str, name: str) -> Optional[dict]:
    """重命名文件，返回更新后的文档（含 content），找不到返回 None。"""
    db = get_db()
    res = await db.files.update_one(
        {"_id": _to_objectid(file_id)},
        {"$set": {"name": name, "updated_at": _now()}},
    )
    if res.matched_count == 0:
        return None
    doc = await db.files.find_one({"_id": _to_objectid(file_id)})
    return _serialize_file(doc, include_content=True)


async def update_file_content(file_id: str, content: str) -> Optional[dict]:
    """修改文件内容，返回更新后的文档（含 content），找不到返回 None。"""
    db = get_db()
    res = await db.files.update_one(
        {"_id": _to_objectid(file_id)},
        {"$set": {"content": content, "updated_at": _now()}},
    )
    if res.matched_count == 0:
        return None
    doc = await db.files.find_one({"_id": _to_objectid(file_id)})
    return _serialize_file(doc, include_content=True)


# ----------------------------- 移动 -----------------------------


async def move_file(file_id: str, target_folder_id: str) -> Optional[dict]:
    """移动文件到目标文件夹，返回更新后的文档，找不到返回 None。"""
    db = get_db()
    res = await db.files.update_one(
        {"_id": _to_objectid(file_id)},
        {"$set": {"parent_id": _to_objectid(target_folder_id), "updated_at": _now()}},
    )
    if res.matched_count == 0:
        return None
    doc = await db.files.find_one({"_id": _to_objectid(file_id)})
    return _serialize_file(doc, include_content=True)


# ----------------------------- 删除 -----------------------------


async def delete_folder(folder_id: str) -> bool:
    """递归删除文件夹：先删子文件、子文件夹（递归），再删自身。"""
    db = get_db()
    oid = _to_objectid(folder_id)
    # 文件夹不存在则视为未删除
    folder = await db.folders.find_one({"_id": oid})
    if folder is None:
        return False
    # 删除直接子文件
    await db.files.delete_many({"parent_id": oid})
    # 递归删除子文件夹
    children = await db.folders.find({"parent_id": oid}).to_list(None)
    for child in children:
        await delete_folder(str(child["_id"]))
    # 删除自身
    await db.folders.delete_one({"_id": oid})
    return True


async def delete_file(file_id: str) -> bool:
    """删除文件，返回是否删除成功。"""
    db = get_db()
    res = await db.files.delete_one({"_id": _to_objectid(file_id)})
    return res.deleted_count > 0


# ----------------------------- 目录树 -----------------------------


async def get_folder_tree() -> list[dict]:
    """返回完整目录树：每个节点含 folder 信息 + children + files。"""
    db = get_db()
    folders = await db.folders.find().to_list(None)
    files = await db.files.find().to_list(None)

    # 按 parent_id 分组
    folders_by_parent: dict = {}
    for f in folders:
        pid = str(f["parent_id"]) if f.get("parent_id") is not None else None
        folders_by_parent.setdefault(pid, []).append(f)
    files_by_parent: dict = {}
    for fi in files:
        pid = str(fi["parent_id"]) if fi.get("parent_id") is not None else None
        files_by_parent.setdefault(pid, []).append(fi)

    def build_node(folder_doc: dict) -> dict:
        node = _serialize_folder(folder_doc)
        fid = str(folder_doc["_id"])
        node["children"] = [build_node(c) for c in folders_by_parent.get(fid, [])]
        node["files"] = [
            _serialize_file(fi, include_content=False) for fi in files_by_parent.get(fid, [])
        ]
        return node

    # 顶级目录按创建时间排序
    roots = sorted(folders_by_parent.get(None, []), key=lambda d: d.get("created_at"))
    return [build_node(f) for f in roots]


# ----------------------------- 按名称查找 -----------------------------


async def find_folders_by_name(name: str, parent_id: Optional[str] = None) -> list[dict]:
    """按名称查找文件夹。parent_id 为 None 表示顶级目录。"""
    db = get_db()
    query: dict = {"name": name}
    if parent_id is None:
        query["parent_id"] = None
    else:
        query["parent_id"] = _to_objectid(parent_id)
    docs = await db.folders.find(query).to_list(None)
    return [_serialize_folder(d) for d in docs]


async def find_files_by_name(name: str, parent_id: Optional[str] = None) -> list[dict]:
    """按名称查找文件。parent_id 为 None 表示匹配 parent_id 为 null 的文件。"""
    db = get_db()
    query: dict = {"name": name}
    if parent_id is None:
        query["parent_id"] = None
    else:
        query["parent_id"] = _to_objectid(parent_id)
    docs = await db.files.find(query).to_list(None)
    return [_serialize_file(d, include_content=True) for d in docs]


# ----------------------------- 路径 -----------------------------


async def get_folder_path(folder_id: str) -> list[dict]:
    """返回从根到该文件夹的路径列表（不含自身？含自身）。

    返回包含该文件夹自身在内的完整路径。
    """
    db = get_db()
    path: list[dict] = []
    current = _to_objectid(folder_id)
    while current is not None:
        folder = await db.folders.find_one({"_id": current})
        if folder is None:
            break
        path.append(_serialize_folder(folder))
        current = folder.get("parent_id")
    path.reverse()
    return path


# ----------------------------- 默认目录 -----------------------------


async def get_default_uncategorized_folder() -> dict:
    """获取/创建"未分类"顶级目录。"""
    db = get_db()
    folder = await db.folders.find_one(
        {"name": UNCATEGORIZED_FOLDER_NAME, "parent_id": None}
    )
    if folder is None:
        now = _now()
        result = await db.folders.insert_one(
            {
                "name": UNCATEGORIZED_FOLDER_NAME,
                "parent_id": None,
                "created_at": now,
                "updated_at": now,
            }
        )
        folder = await db.folders.find_one({"_id": result.inserted_id})
    return _serialize_folder(folder)


def is_valid_id(id_str: str) -> bool:
    """判断字符串是否为合法 ObjectId。"""
    try:
        return ObjectId.is_valid(id_str)
    except (InvalidId, TypeError):
        return False
