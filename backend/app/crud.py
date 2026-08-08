"""数据访问层（folders / files 的 CRUD）。

全部 async，使用 motor。ID 在 API 层用字符串，内部转 ObjectId。
"""

import difflib
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
        "type": doc.get("type", "note"),  # "note" 或 "event"
        "date": doc.get("date", ""),      # 仅 event 类型有值 YYYY-MM-DD
        "time": doc.get("time", ""),      # 仅 event 类型有值 HH:MM
        "reminder_minutes": doc.get("reminder_minutes"),  # 提前多少分钟提醒，None 表示无提醒
        "recurrence": doc.get("recurrence"),              # null/""=一次性，"daily"/"weekly"/"monthly"
        "created_at": _dt_iso(doc.get("created_at")),
        "updated_at": _dt_iso(doc.get("updated_at")),
    }
    if include_content:
        result["content"] = doc.get("content", "")
    return result


def _now() -> datetime:
    """当前 UTC 时间。"""
    return datetime.now(timezone.utc)


def _is_subsequence(query: str, target: str) -> bool:
    """query 的字符是否按顺序出现在 target 中（子序列匹配）。

    例如 "明日会议" 是 "明日重要会议" 的子序列。
    """
    it = iter(target)
    return all(ch in it for ch in query)


def _match_score(query: str, target: str) -> int:
    """模糊匹配打分：0=不匹配，分数越高越优先。

    优先级：精确(100) > 子串(80) > 子序列(60) > 相似度(<=50)。
    """
    if not query or not target:
        return 0
    q = query.strip()
    t = target.strip()
    # 去掉可能的 .md 后缀再比较
    if q.lower().endswith(".md"):
        q = q[:-3]
    if t.lower().endswith(".md"):
        t = t[:-3]
    if not q or not t:
        return 0
    if q == t:
        return 100
    if q in t or t in q:
        return 80
    if _is_subsequence(q, t):
        return 60
    ratio = difflib.SequenceMatcher(None, q, t).ratio()
    if ratio >= 0.6:
        return int(ratio * 50)
    return 0


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


async def create_file(
    name: str,
    content: str,
    parent_id: str,
    file_type: str = "note",
    date: str = "",
    time: str = "",
) -> dict:
    """创建文件。parent_id 必须提供。file_type: "note" 或 "event"。date/time 仅 event 类型使用。"""
    db = get_db()
    now = _now()
    parent_oid = _to_objectid(parent_id)
    doc_data: dict = {
        "name": name,
        "content": content,
        "parent_id": parent_oid,
        "type": file_type,
        "created_at": now,
        "updated_at": now,
    }
    if date:
        doc_data["date"] = date
    if time:
        doc_data["time"] = time
    result = await db.files.insert_one(doc_data)
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


async def find_folder_exact(name: str, parent_id: Optional[str] = None) -> Optional[dict]:
    """精确查找同名同父的文件夹（用于幂等检查）。parent_id=None 表示顶级。

    与 find_folders_by_name 不同：这里要求 parent_id 精确匹配（None 只匹配顶级）。
    """
    db = get_db()
    query: dict = {"name": name}
    if parent_id is None:
        query["parent_id"] = None
    else:
        query["parent_id"] = _to_objectid(parent_id)
    doc = await db.folders.find_one(query)
    return _serialize_folder(doc)


async def find_folders_by_name(name: str, parent_id: Optional[str] = None) -> list[dict]:
    """按名称查找文件夹（模糊匹配）。parent_id 为 None 表示全局搜索。

    匹配优先级：精确 > 子串 > 子序列 > 相似度；结果按匹配度降序。
    """
    db = get_db()
    base_query: dict = {}
    if parent_id is not None:
        base_query["parent_id"] = _to_objectid(parent_id)
    # 1. 精确匹配（优先返回）
    exact = await db.folders.find({**base_query, "name": name}).to_list(None)
    if exact:
        return [_serialize_folder(d) for d in exact]
    # 2. 模糊匹配
    all_docs = await db.folders.find(base_query).to_list(None)
    scored = [(_match_score(name, d.get("name", "")), d) for d in all_docs]
    matched = [d for s, d in scored if s > 0]
    matched.sort(key=lambda d: _match_score(name, d.get("name", "")), reverse=True)
    return [_serialize_folder(d) for d in matched]


async def find_files_by_name(name: str, parent_id: Optional[str] = None) -> list[dict]:
    """按名称查找文件（模糊匹配）。parent_id 为 None 表示全局搜索。

    匹配优先级：精确 > 子串 > 子序列 > 相似度；结果按匹配度降序。
    """
    db = get_db()
    base_query: dict = {}
    if parent_id is not None:
        base_query["parent_id"] = _to_objectid(parent_id)
    # 1. 精确匹配（优先返回）
    exact = await db.files.find({**base_query, "name": name}).to_list(None)
    if exact:
        return [_serialize_file(d, include_content=False) for d in exact]
    # 2. 模糊匹配
    all_docs = await db.files.find(base_query).to_list(None)
    scored = [(_match_score(name, d.get("name", "")), d) for d in all_docs]
    matched = [d for s, d in scored if s > 0]
    matched.sort(key=lambda d: _match_score(name, d.get("name", "")), reverse=True)
    return [_serialize_file(d, include_content=False) for d in matched]


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


# ----------------------------- 日程查询（查 files 中 type=event）------------------------------


async def find_files_by_date(date: str) -> list[dict]:
    """列出某一天（YYYY-MM-DD）的所有日程文件（按 time 排序）。"""
    db = get_db()
    docs = await db.files.find({"type": "event", "date": date}).sort("time", 1).to_list(None)
    return [_serialize_file(d, include_content=True) for d in docs]


async def find_files_by_month(year: int, month: int) -> list[dict]:
    """列出某月所有有日程的日期及数量（用于日历标记）。"""
    db = get_db()
    prefix = f"{year:04d}-{month:02d}"
    pipeline = [
        {"$match": {"type": "event", "date": {"$regex": f"^{prefix}"}}},
        {"$group": {"_id": "$date", "count": {"$sum": 1}}},
        {"$sort": {"_id": 1}},
    ]
    agg = await db.files.aggregate(pipeline).to_list(None)
    return [{"date": a["_id"], "count": a["count"]} for a in agg]


# ----------------------------- 提醒 ------------------------------


async def set_reminder(file_id: str, minutes: int, recurrence: str = "") -> Optional[dict]:
    """为文件设置提醒。minutes=0 取消提醒。recurrence: ""=一次性, "daily"/"weekly"/"monthly"。"""
    db = get_db()
    if minutes > 0:
        set_fields: dict = {"reminder_minutes": minutes, "updated_at": _now()}
        if recurrence:
            set_fields["recurrence"] = recurrence
        else:
            set_fields["recurrence"] = None
        update = {"$set": set_fields}
    else:
        update = {"$unset": {"reminder_minutes": "", "recurrence": ""}, "$set": {"updated_at": _now()}}
    res = await db.files.update_one({"_id": _to_objectid(file_id)}, update)
    if res.matched_count == 0:
        return None
    doc = await db.files.find_one({"_id": _to_objectid(file_id)})
    return _serialize_file(doc, include_content=True)


async def find_files_with_reminders() -> list[dict]:
    """列出所有设置了提醒的文件（按 date+time 排序，仅日程类型）。"""
    db = get_db()
    docs = await db.files.find(
        {"reminder_minutes": {"$exists": True, "$gt": 0}}
    ).sort([("date", 1), ("time", 1)]).to_list(None)
    return [_serialize_file(d, include_content=True) for d in docs]


# ----------------------------- 用户 Profile ------------------------------


def _serialize_user(doc: Optional[dict]) -> Optional[dict]:
    """序列化用户文档。"""
    if doc is None:
        return None
    return {
        "id": str(doc["_id"]),
        "device_id": doc.get("device_id", ""),
        "latitude": doc.get("latitude"),
        "longitude": doc.get("longitude"),
        "home_address": doc.get("home_address", ""),
        "places": doc.get("places", []),  # [{"name": "望金沙", "lat": 30.31, "lon": 120.39}, ...]
        "created_at": _dt_iso(doc.get("created_at")),
        "updated_at": _dt_iso(doc.get("updated_at")),
    }


async def get_or_create_user(device_id: str) -> dict:
    """获取或创建用户 Profile（按 device_id 唯一）。"""
    db = get_db()
    doc = await db.users.find_one({"device_id": device_id})
    if doc is None:
        now = _now()
        result = await db.users.insert_one({
            "device_id": device_id,
            "latitude": None,
            "longitude": None,
            "home_address": "",
            "places": [],
            "created_at": now,
            "updated_at": now,
        })
        doc = await db.users.find_one({"_id": result.inserted_id})
    return _serialize_user(doc)


async def update_user_location(device_id: str, lat: float, lon: float) -> dict | None:
    """更新用户当前位置。"""
    db = get_db()
    res = await db.users.update_one(
        {"device_id": device_id},
        {"$set": {"latitude": lat, "longitude": lon, "updated_at": _now()}},
    )
    if res.matched_count == 0:
        return None
    doc = await db.users.find_one({"device_id": device_id})
    return _serialize_user(doc)


async def add_user_place(device_id: str, name: str, lat: float, lon: float) -> dict | None:
    """添加/更新用户的常用地点。同名则覆盖坐标。"""
    db = get_db()
    user = await db.users.find_one({"device_id": device_id})
    if user is None:
        return None
    places: list = user.get("places", [])
    # 同名覆盖
    updated = False
    for p in places:
        if p.get("name") == name:
            p["lat"] = lat
            p["lon"] = lon
            updated = True
            break
    if not updated:
        places.append({"name": name, "lat": lat, "lon": lon})
    await db.users.update_one(
        {"device_id": device_id},
        {"$set": {"places": places, "updated_at": _now()}},
    )
    doc = await db.users.find_one({"device_id": device_id})
    return _serialize_user(doc)


async def get_user_places(device_id: str) -> list[dict]:
    """获取用户的常用地点列表。"""
    db = get_db()
    user = await db.users.find_one({"device_id": device_id})
    if user is None:
        return []
    return user.get("places", [])
