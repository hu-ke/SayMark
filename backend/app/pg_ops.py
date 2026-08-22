"""PostgreSQL 数据操作层。

PostgreSQL 数据访问层，提供所有读写操作。
"""

import json
import re
from datetime import datetime, timezone
from typing import Optional

from . import pg_db

# 允许的 SQL 关键字白名单（只允许 SELECT 查询）
_SQL_SELECT_PATTERN = re.compile(r"^\s*SELECT\b", re.IGNORECASE)
_SQL_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|EXEC(UTE)?)\b",
    re.IGNORECASE,
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ----------------------------- 安全 SQL 执行 -----------------------------


def validate_sql(sql: str) -> str:
    """校验 SQL 查询安全性。只允许 SELECT，禁止写操作。"""
    if not _SQL_SELECT_PATTERN.match(sql):
        raise ValueError("只允许 SELECT 查询")
    if _SQL_FORBIDDEN.search(sql):
        raise ValueError(f"SQL 包含禁止的关键字")
    # 去末尾分号
    return sql.rstrip(";").strip()


async def run_safe_query(sql: str) -> list[dict]:
    """安全执行 SELECT 查询，返回 dict 列表。"""
    clean = validate_sql(sql)
    return await pg_db.fetch(clean)


_HAS_SCHEDULE = False
_HAS_POSITION = False


async def ensure_schema() -> None:
    """检测新增列是否存在（不执行 ALTER，避免非 owner 用户权限不足）。

    缺失时相关功能自动降级：列表按 created_at 排序、禁用位置交换。
    """
    global _HAS_SCHEDULE, _HAS_POSITION
    rows = await pg_db.fetch(
        "SELECT table_name, column_name FROM information_schema.columns "
        "WHERE (table_name = 'files' AND column_name IN ('schedule', 'position')) "
        "   OR (table_name = 'folders' AND column_name = 'position')"
    )
    _HAS_SCHEDULE = any(
        r["table_name"] == "files" and r["column_name"] == "schedule" for r in rows
    )
    _HAS_POSITION = (
        any(r["table_name"] == "files" and r["column_name"] == "position" for r in rows)
        and any(r["table_name"] == "folders" and r["column_name"] == "position" for r in rows)
    )


def _position_order() -> str:
    """返回排序子句，缺失 position 列时退回 created_at。"""
    return "position, created_at" if _HAS_POSITION else "created_at"


# ----------------------------- 文件夹 -----------------------------


async def create_folder(name: str, parent_id: int | None = None) -> dict:
    """创建文件夹。同名同父已存在则返回已有。"""
    parent_id = int(parent_id) if parent_id is not None else None
    now = _now()
    existing = await pg_db.fetchrow(
        "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name=$1 AND parent_id IS NOT DISTINCT FROM $2",
        name, parent_id,
    )
    if existing:
        return existing
    if _HAS_POSITION:
        result = await pg_db.execute(
            """INSERT INTO folders (name, parent_id, position, created_at, updated_at)
               VALUES ($1, $2, COALESCE((SELECT MAX(position) + 1 FROM folders WHERE parent_id IS NOT DISTINCT FROM $2), 0), $3, $3)
               RETURNING id""",
            name, parent_id, now,
        )
    else:
        result = await pg_db.execute(
            "INSERT INTO folders (name, parent_id, created_at, updated_at) VALUES ($1, $2, $3, $3) RETURNING id",
            name, parent_id, now,
        )
    new_id = int(result.split()[-1])
    return await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1", new_id)


async def get_folder(folder_id: int) -> dict | None:
    folder_id = int(folder_id)
    return await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1", folder_id)


async def list_root_folders() -> list[dict]:
    return await pg_db.fetch(
        f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id IS NULL ORDER BY {_position_order()}"
    )


async def list_children(folder_id: int) -> dict:
    folder_id = int(folder_id)
    order = _position_order()
    folders = await pg_db.fetch(
        f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id=$1 ORDER BY {order}", folder_id
    )
    files = await pg_db.fetch(
        'SELECT id, name, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, created_at, updated_at '
        f"FROM files WHERE parent_id=$1 ORDER BY {order}", folder_id
    )
    return {"folders": folders, "files": files}


async def update_folder_name(folder_id: int, name: str) -> dict | None:
    folder_id = int(folder_id)
    now = _now()
    r = await pg_db.execute("UPDATE folders SET name=$1, updated_at=$2 WHERE id=$3", name, now, folder_id)
    if r.endswith("0"):
        return None
    return await get_folder(folder_id)


async def delete_folder(folder_id: int) -> bool:
    folder_id = int(folder_id)
    r = await pg_db.execute("DELETE FROM folders WHERE id=$1", folder_id)
    return not r.endswith("0")


async def _is_descendant(folder_id: int, target_folder_id: int) -> bool:
    """判断 target_folder_id 是否位于 folder_id 的子树内（用于阻止循环移动）。"""
    rows = await pg_db.fetch("""
        WITH RECURSIVE path AS (
            SELECT id, parent_id FROM folders WHERE id=$1
            UNION ALL
            SELECT f.id, f.parent_id FROM folders f JOIN path p ON f.id = p.parent_id
        )
        SELECT 1 FROM path WHERE id=$2 LIMIT 1
    """, target_folder_id, folder_id)
    return len(rows) > 0


async def move_folder(folder_id: int, target_folder_id: int | None = None) -> dict | None:
    """移动文件夹到目标文件夹（target_folder_id 为 None 表示顶级）。"""
    folder_id = int(folder_id)
    if target_folder_id is not None:
        target_folder_id = int(target_folder_id)
        if folder_id == target_folder_id:
            raise ValueError("不能将文件夹移动到自身")
        if await _is_descendant(folder_id, target_folder_id):
            raise ValueError("不能将文件夹移动到其子文件夹中")
    now = _now()
    r = await pg_db.execute("UPDATE folders SET parent_id=$1, updated_at=$2 WHERE id=$3", target_folder_id, now, folder_id)
    if r.endswith("0"):
        return None
    return await get_folder(folder_id)


async def swap_item_positions(item_type: str, id1: int, id2: int) -> bool:
    """交换两个同类型、同一父级项的位置（type: 'file' 或 'folder'）。"""
    if not _HAS_POSITION:
        raise ValueError("数据库缺少 position 字段，无法交换位置；请以数据库所有者身份运行 setup_pg.sql 迁移")
    if item_type not in ("file", "folder"):
        raise ValueError("type 必须为 file 或 folder")
    id1 = int(id1)
    id2 = int(id2)
    if id1 == id2:
        return True

    table = "files" if item_type == "file" else "folders"
    row1 = await pg_db.fetchrow_raw(f"SELECT id, parent_id FROM {table} WHERE id=$1", id1)
    row2 = await pg_db.fetchrow_raw(f"SELECT id, parent_id FROM {table} WHERE id=$1", id2)
    if row1 is None or row2 is None:
        return False
    if row1["parent_id"] != row2["parent_id"]:
        raise ValueError("只能交换同一层级下的两个项")

    # 先归一化同级位置（历史数据 position 可能都为 0）
    siblings = await pg_db.fetch_raw(
        f"SELECT id FROM {table} WHERE parent_id IS NOT DISTINCT FROM $1 ORDER BY position, created_at, id",
        row1["parent_id"],
    )
    pos_by_id: dict[int, int] = {}
    for idx, s in enumerate(siblings):
        pos_by_id[s["id"]] = idx
        await pg_db.execute(f"UPDATE {table} SET position=$1 WHERE id=$2", idx, s["id"])

    await pg_db.execute(f"UPDATE {table} SET position=$1 WHERE id=$2", pos_by_id[id2], id1)
    await pg_db.execute(f"UPDATE {table} SET position=$1 WHERE id=$2", pos_by_id[id1], id2)
    return True


async def get_folder_path(folder_id: int) -> list[dict]:
    """返回从根到该文件夹的路径。"""
    folder_id = int(folder_id)
    rows = await pg_db.fetch("""
        WITH RECURSIVE path AS (
            SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1
            UNION ALL
            SELECT f.id, f.name, f.parent_id, f.created_at, f.updated_at
            FROM folders f JOIN path p ON f.id = p.parent_id
        )
        SELECT * FROM path
    """, folder_id)
    rows.reverse()
    return rows


async def get_default_uncategorized_folder() -> dict:
    f = await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name='未分类' AND parent_id IS NULL")
    if f is None:
        return await create_folder("未分类")
    return f


# ----------------------------- 文件 -----------------------------


async def create_file(
    name: str, content: str, parent_id: int,
    file_type: str = "note", date: str = "", time: str = "",
    schedule: Optional[dict] = None,
) -> dict:
    parent_id = int(parent_id)
    now = _now()

    # 日程属性统一以 schedule JSON 为准（新创建入口）；老入口仍兼容 date/time/file_type 传参
    if schedule is not None:
        file_type = "event"
        date = str(schedule.get("date") or date)
        time = str(schedule.get("time") or time)
        schedule_json = json.dumps(schedule, ensure_ascii=False)
    elif file_type == "event":
        schedule_json = json.dumps({
            "date": date, "time": time,
            "repeat": {"enabled": False, "unit": "", "value": 0},
        }, ensure_ascii=False)
    else:
        schedule_json = ""

    date_obj = datetime.strptime(date, "%Y-%m-%d").date() if date else None
    time_obj = datetime.strptime(time, "%H:%M").time() if time else None

    if _HAS_SCHEDULE and _HAS_POSITION:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", schedule, position, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7,
                         COALESCE((SELECT MAX(position) + 1 FROM files WHERE parent_id = $3), 0), $8, $8)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, schedule_json, now]
    elif _HAS_SCHEDULE:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", schedule, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, schedule_json, now]
    elif _HAS_POSITION:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", position, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6,
                         COALESCE((SELECT MAX(position) + 1 FROM files WHERE parent_id = $3), 0), $7, $7)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, now]
    else:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, now]

    result = await pg_db.execute(sql, *args)
    new_id = int(result.split()[-1])
    return await get_file(new_id)


async def get_file(file_id: int) -> dict | None:
    file_id = int(file_id)
    if _HAS_SCHEDULE:
        sql = 'SELECT id, name, content, parent_id, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, schedule, created_at, updated_at FROM files WHERE id=$1'
    else:
        sql = 'SELECT id, name, content, parent_id, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, created_at, updated_at FROM files WHERE id=$1'
    return await pg_db.fetchrow(sql, file_id)


async def update_file_name(file_id: int, name: str) -> dict | None:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET name=$1, updated_at=$2 WHERE id=$3", name, now, file_id)
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def update_file_content(file_id: int, content: str) -> dict | None:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET content=$1, updated_at=$2 WHERE id=$3", content, now, file_id)
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def move_file(file_id: int, target_folder_id: int) -> dict | None:
    file_id = int(file_id)
    target_folder_id = int(target_folder_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET parent_id=$1, updated_at=$2 WHERE id=$3", target_folder_id, now, file_id)
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def delete_file(file_id: int) -> bool:
    file_id = int(file_id)
    r = await pg_db.execute("DELETE FROM files WHERE id=$1", file_id)
    return not r.endswith("0")


async def set_reminder(file_id: int, minutes: int, recurrence: str = "", recurrence_end_date: str = "") -> dict | None:
    file_id = int(file_id)
    now = _now()
    end_date_obj = datetime.strptime(recurrence_end_date, "%Y-%m-%d").date() if recurrence_end_date else None
    if minutes > 0:
        r = await pg_db.execute(
            "UPDATE files SET reminder_minutes=$1, recurrence=NULLIF($2,''), recurrence_end_date=$3, updated_at=$4 WHERE id=$5",
            minutes, recurrence or None, end_date_obj, now, file_id,
        )
    else:
        r = await pg_db.execute(
            "UPDATE files SET reminder_minutes=NULL, recurrence=NULL, recurrence_end_date=NULL, updated_at=$1 WHERE id=$2",
            now, file_id,
        )
    if r.endswith("0"):
        return None
    return await get_file(file_id)


# ----------------------------- 语义搜索 -----------------------------


async def update_file_embedding(file_id: int, embedding: list[float]) -> bool:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET embedding=$1::FLOAT8[], updated_at=$2 WHERE id=$3", embedding, now, file_id)
    return not r.endswith("0")


async def search_files_semantic(query_text: str, top_k: int = 10, threshold: float = 0.5) -> list[dict]:
    """语义搜索：生成 query embedding，与库中文件做余弦相似度计算。"""
    from .services import qwen

    query_vec = await qwen.embed(query_text)
    # 查询所有有 embedding 的文件，Python 侧计算余弦相似度
    rows = await pg_db.fetch("SELECT id, name, type, date, time, created_at, updated_at, embedding FROM files WHERE embedding IS NOT NULL AND array_length(embedding,1) > 0")
    results = []
    for row in rows:
        doc_vec = row.get("embedding")
        if not doc_vec or len(doc_vec) != len(query_vec):
            continue
        sim = _cosine_similarity(query_vec, doc_vec)
        if sim >= threshold:
            del row["embedding"]
            row["_similarity"] = sim
            results.append(row)
    results.sort(key=lambda x: x["_similarity"], reverse=True)
    return results[:top_k]


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(x * x for x in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


# ----------------------------- 用户 -----------------------------


async def get_or_create_user(device_id: str) -> dict:
    user = await pg_db.fetchrow("SELECT id, device_id, latitude, longitude, home_address, created_at, updated_at FROM users WHERE device_id=$1", device_id)
    if user is None:
        now = _now()
        result = await pg_db.execute("INSERT INTO users (device_id, created_at, updated_at) VALUES ($1, $2, $2) RETURNING id", device_id, now)
        new_id = int(result.split()[-1])
        user = await pg_db.fetchrow("SELECT id, device_id, latitude, longitude, home_address, created_at, updated_at FROM users WHERE id=$1", new_id)
    return user


async def update_user_location(device_id: str, lat: float, lon: float) -> dict | None:
    now = _now()
    r = await pg_db.execute("UPDATE users SET latitude=$1, longitude=$2, updated_at=$3 WHERE device_id=$4", lat, lon, now, device_id)
    if r.endswith("0"):
        return None
    return await pg_db.fetchrow("SELECT id, device_id, latitude, longitude, home_address, created_at, updated_at FROM users WHERE device_id=$1", device_id)


async def get_user_places(device_id: str) -> list[dict]:
    return await pg_db.fetch("""
        SELECT up.name, up.lat, up.lon FROM user_places up
        JOIN users u ON up.user_id = u.id WHERE u.device_id = $1
    """, device_id)


async def add_user_place(device_id: str, name: str, lat: float, lon: float) -> dict | None:
    user = await pg_db.fetchrow_raw("SELECT id FROM users WHERE device_id=$1", device_id)
    if user is None:
        return None
    user_id = user["id"]
    await pg_db.execute(
        """INSERT INTO user_places (user_id, name, lat, lon)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (user_id, name) DO UPDATE SET lat=$3, lon=$4""",
        user_id, name, lat, lon,
    )
    return await pg_db.fetchrow("SELECT id, device_id, latitude, longitude, home_address, created_at, updated_at FROM users WHERE id=$1", user_id)


# ----------------------------- 目录树（兼容旧接口） -----------------------------


async def get_folder_tree() -> list[dict]:
    """返回完整目录树。"""
    order = _position_order()
    folders = await pg_db.fetch(f"SELECT id, name, parent_id, created_at, updated_at FROM folders ORDER BY {order}")
    files = await pg_db.fetch(
        'SELECT id, name, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, created_at, updated_at, parent_id '
        f"FROM files ORDER BY {order}"
    )

    folders_by_parent: dict = {}
    for f in folders:
        pid = f["parent_id"]
        folders_by_parent.setdefault(pid, []).append(f)
    files_by_parent: dict = {}
    for fi in files:
        pid = fi["parent_id"]
        files_by_parent.setdefault(pid, []).append(fi)

    def build_node(folder_doc: dict) -> dict:
        fid = folder_doc["id"]
        child_folders = [build_node(c) for c in folders_by_parent.get(fid, [])]
        child_files = files_by_parent.get(fid, [])
        return {**folder_doc, "children": child_folders, "files": child_files}

    roots = list(folders_by_parent.get(None, []))
    return [build_node(r) for r in roots]


# ----------------------------- 兼容旧 command_parser 接口 -----------------------------


async def find_files_by_created_date(date_str: str) -> list[dict]:
    """列出某一天（YYYY-MM-DD）创建的所有文件。"""
    target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    rows = await pg_db.fetch(
        "SELECT id, name, type, date, time, created_at, updated_at FROM files WHERE created_at::date = $1 ORDER BY created_at DESC",
        target_date,
    )
    return rows


async def find_files_by_filter(f: dict, limit: int = 50) -> list[dict]:
    """通用文件查询（兼容旧接口，内部转为 SQL）。"""
    conditions: list[str] = []
    params: list = []
    idx = 1

    # 处理简单字段
    for field in ("type", "date", "parent_id"):
        val = f.get(field)
        if val is not None:
            conditions.append(f"{field}=${idx}")
            params.append(val)
            idx += 1

    # name regex → ILIKE
    name_filter = f.get("name")
    if isinstance(name_filter, dict):
        regex = name_filter.get("$regex", "")
        if regex:
            conditions.append(f"name ILIKE ${idx}")
            params.append(f"%{regex}%")
            idx += 1

    # created_at range
    created = f.get("created_at")
    if isinstance(created, dict):
        gte = created.get("$gte")
        lte = created.get("$lte")
        if gte:
            conditions.append(f"created_at >= ${idx}::date")
            params.append(datetime.strptime(str(gte)[:10], "%Y-%m-%d").date())
            idx += 1
        if lte:
            conditions.append(f"created_at < ${idx}::date")
            params.append(datetime.strptime(str(lte)[:10], "%Y-%m-%d").date())
            idx += 1

    where = "WHERE " + " AND ".join(conditions) if conditions else ""
    query = f"SELECT id, name, type, date, time, created_at, updated_at FROM files {where} ORDER BY created_at DESC LIMIT {limit}"
    return await pg_db.fetch(query, *params)


async def find_folders_by_filter(f: dict, limit: int = 50) -> list[dict]:
    """通用文件夹查询。"""
    conditions: list[str] = []
    params: list = []
    idx = 1

    for field in ("parent_id",):
        val = f.get(field)
        if val is not None:
            conditions.append(f"{field}=${idx}")
            params.append(val)
            idx += 1

    name_filter = f.get("name")
    if isinstance(name_filter, dict):
        regex = name_filter.get("$regex", "")
        if regex:
            conditions.append(f"name ILIKE ${idx}")
            params.append(f"%{regex}%")
            idx += 1

    where = "WHERE " + " AND ".join(conditions) if conditions else ""
    query = f"SELECT id, name, parent_id, created_at, updated_at FROM folders {where} ORDER BY created_at DESC LIMIT {limit}"
    return await pg_db.fetch(query, *params)


async def find_files_by_date(date: str) -> list[dict]:
    """列出某天的事件（按 time 排序）。"""
    target_date = datetime.strptime(date, "%Y-%m-%d").date()
    return await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, created_at, updated_at '
        'FROM files WHERE type=$1 AND date=$2 ORDER BY "time"',
        "event", target_date,
    )


async def find_files_by_month(year: int, month: int) -> list[dict]:
    """列出某月有事件的日期及数量。"""
    prefix = f"{year:04d}-{month:02d}"
    rows = await pg_db.fetch(
        "SELECT date, COUNT(*) AS count FROM files WHERE type='event' AND date::text LIKE $1 GROUP BY date ORDER BY date",
        f"{prefix}%",
    )
    return [{"date": r["date"].isoformat() if hasattr(r["date"], "isoformat") else str(r["date"]), "count": r["count"]} for r in rows]


async def find_files_with_reminders() -> list[dict]:
    """列出所有有提醒的文件。"""
    return await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", reminder_minutes, recurrence, recurrence_end_date, created_at, updated_at '
        "FROM files WHERE reminder_minutes IS NOT NULL AND reminder_minutes > 0 ORDER BY date"
    )
