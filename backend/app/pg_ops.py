"""PostgreSQL 数据操作层。

PostgreSQL 数据访问层，提供所有读写操作。
"""

import contextvars
import re
from datetime import datetime, timezone
from typing import Optional

from loguru import logger

from . import pg_db

# 当前请求的设备标识（数据隔离用），由 main.py 中间件或路由设置
_device_ctx = contextvars.ContextVar("saymark_device_id", default="")


def set_device_id(did: str) -> None:
    """设置当前上下文的设备标识。"""
    _device_ctx.set(did)


def _did() -> str:
    """返回当前上下文的设备标识。"""
    return _device_ctx.get() or ""


# 允许的 SQL 关键字白名单（只允许 SELECT 查询）
_SQL_SELECT_PATTERN = re.compile(r"^\s*SELECT\b", re.IGNORECASE)
_SQL_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|EXEC(UTE)?)\b",
    re.IGNORECASE,
)

# checklist 条目：形如 "- [ ]" / "- [x]"（支持 "-" 或 "*" 前缀）
_TODO_RE = re.compile(r"^\s*[-*]\s*\[([ xX])\]", re.MULTILINE)


def _todo_stats(content) -> tuple[int, int]:
    """统计内容中的 checklist 总数与已完成数，返回 (total, done)。"""
    if not content:
        return 0, 0
    items = _TODO_RE.findall(content)
    total = len(items)
    done = sum(1 for m in items if m in ("x", "X"))
    return total, done


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


def _append_device_filter(sql: str, did: str) -> str:
    """给针对 files/folders 的 SELECT 追加 device_id 过滤（尽力而为）。"""
    escaped = did.replace("'", "''")
    if re.search(r"\bwhere\b", sql, re.IGNORECASE):
        return re.sub(r"\b(where)\b", r"\1 device_id='" + escaped + r"' AND", sql, count=1, flags=re.IGNORECASE)
    m = re.search(r"\bfrom\s+(files|folders)\b(\s+(?:as\s+)?\w+)?", sql, re.IGNORECASE)
    if m:
        return sql[: m.end()] + " WHERE device_id='" + escaped + "'" + sql[m.end():]
    return sql


async def run_scoped_query(sql: str) -> list[dict]:
    """执行带设备隔离的 SELECT 查询（供 AI run_query 工具使用）。"""
    clean = validate_sql(sql)
    did = _did()
    if did and re.search(r"\bfrom\s+(files|folders)\b", clean, re.IGNORECASE):
        clean = _append_device_filter(clean, did)
    return await pg_db.fetch(clean)


_HAS_POSITION = False


async def ensure_schema() -> None:
    """启动时补齐必要结构（position 列、files.type 列宽与 CHECK）。"""
    global _HAS_POSITION
    rows = await pg_db.fetch(
        "SELECT table_name, column_name FROM information_schema.columns "
        "WHERE (table_name = 'files' AND column_name = 'position') "
        "   OR (table_name = 'folders' AND column_name = 'position')"
    )
    _HAS_POSITION = (
        any(r["table_name"] == "files" and r["column_name"] == "position" for r in rows)
        and any(r["table_name"] == "folders" and r["column_name"] == "position" for r in rows)
    )
    await _migrate_files_type()
    await _migrate_archive_columns()
    await _migrate_device_columns()


async def _migrate_device_columns() -> None:
    """为已有库补齐 device_id 字段（数据隔离）。"""
    statements = [
        "ALTER TABLE folders ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT ''",
        "ALTER TABLE files ADD COLUMN IF NOT EXISTS device_id VARCHAR(255) NOT NULL DEFAULT ''",
    ]
    for stmt in statements:
        try:
            await pg_db.execute(stmt)
        except Exception as e:
            logger.warning(f"补齐 device_id 字段失败：{e}（若账号无 DDL/owner 权限，请以表 owner 身份运行 backend/setup_pg.sql）")


async def claim_legacy_data(did: str) -> None:
    """将历史 device_id='' 的数据一次性归入首个连接的设备（数据隔离迁移）。"""
    if not did:
        return
    has = await pg_db.fetchrow(
        "SELECT 1 FROM folders WHERE device_id=$1 UNION ALL SELECT 1 FROM files WHERE device_id=$1 LIMIT 1", did
    )
    if has:
        return
    legacy = await pg_db.fetchrow(
        "SELECT 1 FROM folders WHERE device_id='' UNION ALL SELECT 1 FROM files WHERE device_id='' LIMIT 1"
    )
    if not legacy:
        return
    await pg_db.execute("UPDATE folders SET device_id=$1 WHERE device_id=''", did)
    await pg_db.execute("UPDATE files SET device_id=$1 WHERE device_id=''", did)
    logger.info(f"已将历史数据迁移到设备 {did}")


async def _migrate_archive_columns() -> None:
    """为已有库补齐归档字段（archived / archived_parent_id / archived_path）。"""
    statements = [
        "ALTER TABLE files ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE files ADD COLUMN IF NOT EXISTS archived_parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL",
        "ALTER TABLE files ADD COLUMN IF NOT EXISTS archived_path TEXT DEFAULT ''",
    ]
    for stmt in statements:
        try:
            await pg_db.execute(stmt)
        except Exception as e:
            logger.warning(f"补齐归档字段失败：{e}（若账号无 DDL/owner 权限，请以表 owner 身份运行 backend/setup_pg.sql）")


async def _migrate_files_type() -> None:
    """把 files.type 加宽到 VARCHAR(20) 并更新 CHECK（支持 appointment/alarm）。

    早期库的 type 列是 VARCHAR(10)，装不下 'appointment'（11 字符）。这里自动迁移，
    避免用户手动执行 setup_pg.sql。若当前账号无 DDL 权限（如非表 owner），则记录
    告警并跳过；此时需由数据库所有者手动执行 setup_pg.sql 或授予该表 owner 权限。
    """
    try:
        row = await pg_db.fetchrow(
            "SELECT character_maximum_length FROM information_schema.columns "
            "WHERE table_name='files' AND column_name='type'"
        )
        length = (row or {}).get("character_maximum_length")
        if length is not None and int(length) >= 20:
            return  # 列已够宽，无需迁移
    except Exception as e:
        logger.warning(f"检查 files.type 列宽失败：{e}")
        return

    logger.warning("files.type 列宽不足，尝试自动迁移为 VARCHAR(20)")

    # 迁移顺序：先去掉旧 CHECK，加宽列，再转换旧数据，最后加新 CHECK
    try:
        await pg_db.execute("ALTER TABLE files DROP CONSTRAINT IF EXISTS files_type_check")
    except Exception as e:
        logger.warning(f"删除 files_type_check 约束失败：{e}")
    try:
        await pg_db.execute("ALTER TABLE files ALTER COLUMN type TYPE VARCHAR(20)")
    except Exception as e:
        logger.warning(f"加宽 files.type 列失败：{e}")
    try:
        await pg_db.execute("UPDATE files SET type='appointment' WHERE type='event'")
    except Exception as e:
        logger.warning(f"迁移 type='event' -> 'appointment' 失败：{e}")
    try:
        await pg_db.execute(
            "UPDATE files SET type='alarm' WHERE type='appointment' AND recurrence IS NOT NULL AND recurrence <> ''"
        )
    except Exception as e:
        logger.warning(f"迁移 type -> 'alarm' 失败：{e}")
    try:
        await pg_db.execute(
            "ALTER TABLE files ADD CONSTRAINT files_type_check CHECK (type IN ('note','appointment','alarm')) NOT VALID"
        )
    except Exception as e:
        logger.warning(f"新增 files_type_check 约束失败：{e}")


def _position_order() -> str:
    """返回排序子句，缺失 position 列时退回 created_at。"""
    return "position, created_at" if _HAS_POSITION else "created_at"


# ----------------------------- 文件夹 -----------------------------


async def create_folder(name: str, parent_id: int | None = None) -> dict:
    """创建文件夹。同名同父已存在则返回已有。"""
    parent_id = int(parent_id) if parent_id is not None else None
    now = _now()
    did = _did()
    existing = await pg_db.fetchrow(
        "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name=$1 AND parent_id IS NOT DISTINCT FROM $2 AND device_id=$3",
        name, parent_id, did,
    )
    if existing:
        return existing
    if _HAS_POSITION:
        result = await pg_db.execute(
            """INSERT INTO folders (name, parent_id, device_id, position, created_at, updated_at)
               VALUES ($1, $2, $3, COALESCE((SELECT MAX(position) + 1 FROM folders WHERE parent_id IS NOT DISTINCT FROM $2 AND device_id=$3::varchar), 0), $4, $4)
               RETURNING id""",
            name, parent_id, did, now,
        )
    else:
        result = await pg_db.execute(
            "INSERT INTO folders (name, parent_id, device_id, created_at, updated_at) VALUES ($1, $2, $3, $4, $4) RETURNING id",
            name, parent_id, did, now,
        )
    new_id = int(result.split()[-1])
    return await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1 AND device_id=$2", new_id, did)


async def get_folder(folder_id: int) -> dict | None:
    folder_id = int(folder_id)
    return await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1 AND device_id=$2", folder_id, _did())


async def list_root_folders() -> list[dict]:
    return await pg_db.fetch(
        f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id IS NULL AND device_id=$1 ORDER BY {_position_order()}", _did()
    )


async def list_children(folder_id: int) -> dict:
    folder_id = int(folder_id)
    order = _position_order()
    did = _did()
    folders = await pg_db.fetch(
        f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id=$1 AND device_id=$2 ORDER BY {order}", folder_id, did
    )
    files = await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", recurrence, created_at, updated_at'
        f" FROM files WHERE parent_id=$1 AND type='note' AND archived=FALSE AND device_id=$2 ORDER BY {order}", folder_id, did
    )
    for f in files:
        f["todo_total"], f["todo_done"] = _todo_stats(f.pop("content", None))
    return {"folders": folders, "files": files}


async def update_folder_name(folder_id: int, name: str) -> dict | None:
    folder_id = int(folder_id)
    now = _now()
    r = await pg_db.execute("UPDATE folders SET name=$1, updated_at=$2 WHERE id=$3 AND device_id=$4", name, now, folder_id, _did())
    if r.endswith("0"):
        return None
    return await get_folder(folder_id)


async def delete_folder(folder_id: int) -> bool:
    folder_id = int(folder_id)
    r = await pg_db.execute("DELETE FROM folders WHERE id=$1 AND device_id=$2", folder_id, _did())
    logger.info(f"[delete] 删除文件夹 id={folder_id}")
    return not r.endswith("0")


async def _is_descendant(folder_id: int, target_folder_id: int) -> bool:
    """判断 target_folder_id 是否位于 folder_id 的子树内（用于阻止循环移动）。"""
    did = _did()
    rows = await pg_db.fetch("""
        WITH RECURSIVE path AS (
            SELECT id, parent_id FROM folders WHERE id=$1 AND device_id=$2
            UNION ALL
            SELECT f.id, f.parent_id FROM folders f JOIN path p ON f.id = p.parent_id
        )
        SELECT 1 FROM path WHERE id=$3 LIMIT 1
    """, target_folder_id, did, folder_id)
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
    r = await pg_db.execute("UPDATE folders SET parent_id=$1, updated_at=$2 WHERE id=$3 AND device_id=$4", target_folder_id, now, folder_id, _did())
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

    did = _did()
    table = "files" if item_type == "file" else "folders"
    row1 = await pg_db.fetchrow_raw(f"SELECT id, parent_id FROM {table} WHERE id=$1 AND device_id=$2", id1, did)
    row2 = await pg_db.fetchrow_raw(f"SELECT id, parent_id FROM {table} WHERE id=$1 AND device_id=$2", id2, did)
    if row1 is None or row2 is None:
        return False
    if row1["parent_id"] != row2["parent_id"]:
        raise ValueError("只能交换同一层级下的两个项")

    # 先归一化同级位置（历史数据 position 可能都为 0）
    siblings = await pg_db.fetch_raw(
        f"SELECT id FROM {table} WHERE parent_id IS NOT DISTINCT FROM $1 AND device_id=$2 ORDER BY position, created_at, id",
        row1["parent_id"], did,
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
            SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id=$1 AND device_id=$2
            UNION ALL
            SELECT f.id, f.name, f.parent_id, f.created_at, f.updated_at
            FROM folders f JOIN path p ON f.id = p.parent_id
        )
        SELECT * FROM path
    """, folder_id, _did())
    rows.reverse()
    return rows


async def get_default_uncategorized_folder() -> dict:
    did = _did()
    f = await pg_db.fetchrow("SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE name='未分类' AND parent_id IS NULL AND device_id=$1", did)
    if f is None:
        return await create_folder("未分类")
    return f


# ----------------------------- 文件 -----------------------------


async def create_file(
    name: str, content: str, parent_id: int | None,
    file_type: str = "note", date: str = "", time: str = "",
    recurrence: Optional[str] = None,
) -> dict:
    """创建文件。file_type: note | appointment | alarm。

    note 需要 parent_id；appointment/alarm 的 parent_id 传 None（不归属文件夹）。
    """
    parent_id = int(parent_id) if parent_id is not None else None
    now = _now()
    did = _did()

    # 容错：date/time 可能带秒/时区（如 "13:00:00"、"2026-08-22T..."），截断为标准格式
    date = (date or "")[:10]
    time = (time or "")[:5]
    date_obj = datetime.strptime(date, "%Y-%m-%d").date() if date else None
    time_obj = datetime.strptime(time, "%H:%M").time() if time else None
    recurrence = (recurrence or None) if file_type == "alarm" else None

    if _HAS_POSITION:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", recurrence, device_id, position, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8,
                         COALESCE((SELECT MAX(position) + 1 FROM files WHERE parent_id IS NOT DISTINCT FROM $3 AND device_id=$8::varchar), 0), $9, $9)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, recurrence, did, now]
    else:
        sql = """INSERT INTO files (name, content, parent_id, type, date, "time", recurrence, device_id, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
                 RETURNING id"""
        args = [name, content, parent_id, file_type, date_obj, time_obj, recurrence, did, now]

    result = await pg_db.execute(sql, *args)
    new_id = int(result.split()[-1])
    return await get_file(new_id)


async def get_file(file_id: int) -> dict | None:
    file_id = int(file_id)
    sql = 'SELECT id, name, content, parent_id, type, date, "time", recurrence, archived, archived_parent_id, archived_path, created_at, updated_at FROM files WHERE id=$1 AND device_id=$2'
    row = await pg_db.fetchrow(sql, file_id, _did())
    if row is None:
        return None
    row["todo_total"], row["todo_done"] = _todo_stats(row.get("content"))
    return row


async def update_file_name(file_id: int, name: str) -> dict | None:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET name=$1, updated_at=$2 WHERE id=$3 AND device_id=$4", name, now, file_id, _did())
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def update_file_content(file_id: int, content: str) -> dict | None:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET content=$1, updated_at=$2 WHERE id=$3 AND device_id=$4", content, now, file_id, _did())
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def move_file(file_id: int, target_folder_id: int) -> dict | None:
    file_id = int(file_id)
    target_folder_id = int(target_folder_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET parent_id=$1, updated_at=$2 WHERE id=$3 AND device_id=$4", target_folder_id, now, file_id, _did())
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def delete_file(file_id: int) -> bool:
    file_id = int(file_id)
    r = await pg_db.execute("DELETE FROM files WHERE id=$1 AND device_id=$2", file_id, _did())
    logger.info(f"[delete] 删除文件 id={file_id}")
    return not r.endswith("0")


# ----------------------------- 归档 -----------------------------


async def archive_file(file_id: int) -> dict | None:
    """归档文件：记录原文件夹与路径快照，并移出文件夹（parent_id 置 NULL）。"""
    file_id = int(file_id)
    did = _did()
    row = await pg_db.fetchrow_raw("SELECT id, parent_id FROM files WHERE id=$1 AND device_id=$2", file_id, did)
    if row is None:
        return None
    parent_id = row["parent_id"]
    archived_path = ""
    if parent_id is not None:
        path_rows = await get_folder_path(parent_id)
        archived_path = "/".join(f["name"] for f in path_rows)
    logger.info(f"[archive] 归档文件 id={file_id} 原路径={archived_path or '顶级'} device={did}")
    now = _now()
    await pg_db.execute(
        "UPDATE files SET archived=TRUE, archived_parent_id=$1, archived_path=$2, parent_id=NULL, updated_at=$3 WHERE id=$4 AND device_id=$5",
        parent_id, archived_path, now, file_id, did,
    )
    return await get_file(file_id)


async def restore_file(file_id: int, target_folder_id: int | None = None) -> dict | None:
    """恢复归档文件到原处或移动到指定文件夹。"""
    file_id = int(file_id)
    did = _did()
    row = await pg_db.fetchrow_raw(
        "SELECT id, archived_parent_id FROM files WHERE id=$1 AND device_id=$2", file_id, did
    )
    if row is None:
        return None
    if target_folder_id is None:
        original_parent = row.get("archived_parent_id")
        if original_parent is None:
            raise ValueError("原路径不存在")
        folder = await get_folder(original_parent)
        if folder is None:
            raise ValueError("原路径不存在")
        new_parent = original_parent
    else:
        new_parent = int(target_folder_id)
    now = _now()
    await pg_db.execute(
        "UPDATE files SET parent_id=$1, archived=FALSE, archived_parent_id=NULL, archived_path='', updated_at=$2 WHERE id=$3 AND device_id=$4",
        new_parent, now, file_id, did,
    )
    return await get_file(file_id)


async def list_archived_files() -> list[dict]:
    """列出所有已归档文件（按归档时间倒序），附带 checklist 统计。"""
    rows = await pg_db.fetch(
        "SELECT id, name, content, archived_path, created_at, updated_at FROM files WHERE archived=TRUE AND device_id=$1 ORDER BY updated_at DESC", _did()
    )
    result = []
    for r in rows:
        content = r.pop("content", None)
        r["todo_total"], r["todo_done"] = _todo_stats(content)
        result.append(r)
    return result


async def update_appointment(
    file_id: int,
    name: Optional[str] = None,
    date: Optional[str] = None,
    time: Optional[str] = None,
    content: Optional[str] = None,
) -> dict | None:
    """更新安排（一次性）。None 表示不改动。"""
    file_id = int(file_id)
    file = await get_file(file_id)
    if file is None:
        return None

    now = _now()

    new_name = name if name is not None else file.get("name")
    new_content = content if content is not None else file.get("content")

    existing_date = str(file.get("date") or "")
    existing_time = str(file.get("time") or "")
    new_date = (str(date)[:10] if date else "") if date is not None else existing_date[:10]
    new_time = (str(time)[:5] if time else "") if time is not None else existing_time[:5]

    date_obj = datetime.strptime(new_date, "%Y-%m-%d").date() if new_date else None
    time_obj = datetime.strptime(new_time, "%H:%M").time() if new_time else None

    r = await pg_db.execute(
        'UPDATE files SET name=$1, content=$2, date=$3, "time"=$4, updated_at=$5 WHERE id=$6 AND device_id=$7',
        new_name, new_content, date_obj, time_obj, now, file_id, _did(),
    )
    if r.endswith("0"):
        return None
    return await get_file(file_id)


async def update_alarm(
    file_id: int,
    name: Optional[str] = None,
    time: Optional[str] = None,
    recurrence: Optional[str] = None,
    content: Optional[str] = None,
) -> dict | None:
    """更新闹钟（周期性）。None 表示不改动。"""
    file_id = int(file_id)
    file = await get_file(file_id)
    if file is None:
        return None

    now = _now()

    new_name = name if name is not None else file.get("name")
    new_content = content if content is not None else file.get("content")

    existing_time = str(file.get("time") or "")
    new_time = (str(time)[:5] if time else "") if time is not None else existing_time[:5]
    new_recurrence = (recurrence or None) if recurrence is not None else file.get("recurrence")

    time_obj = datetime.strptime(new_time, "%H:%M").time() if new_time else None

    r = await pg_db.execute(
        'UPDATE files SET name=$1, content=$2, "time"=$3, recurrence=$4, updated_at=$5 WHERE id=$6 AND device_id=$7',
        new_name, new_content, time_obj, new_recurrence, now, file_id, _did(),
    )
    if r.endswith("0"):
        return None
    return await get_file(file_id)


# ----------------------------- 语义搜索 -----------------------------


async def update_file_embedding(file_id: int, embedding: list[float]) -> bool:
    file_id = int(file_id)
    now = _now()
    r = await pg_db.execute("UPDATE files SET embedding=$1::FLOAT8[], updated_at=$2 WHERE id=$3 AND device_id=$4", embedding, now, file_id, _did())
    return not r.endswith("0")


async def search_files_semantic(query_text: str, top_k: int = 10, threshold: float = 0.5) -> list[dict]:
    """语义搜索：生成 query embedding，与库中文件做余弦相似度计算。"""
    from .services import qwen

    query_vec = await qwen.embed(query_text)
    # 查询所有有 embedding 的文件，Python 侧计算余弦相似度
    rows = await pg_db.fetch("SELECT id, name, type, date, time, created_at, updated_at, embedding FROM files WHERE embedding IS NOT NULL AND array_length(embedding,1) > 0 AND device_id=$1", _did())
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


async def update_user_location(device_id: str, lat: float, lon: float) -> dict:
    # 用户不存在时自动创建，避免首次上报位置时 404
    await get_or_create_user(device_id)
    now = _now()
    await pg_db.execute(
        "UPDATE users SET latitude=$1, longitude=$2, updated_at=$3 WHERE device_id=$4",
        lat, lon, now, device_id,
    )
    return await pg_db.fetchrow("SELECT id, device_id, latitude, longitude, home_address, created_at, updated_at FROM users WHERE device_id=$1", device_id)


async def get_user_places(device_id: str) -> list[dict]:
    return await pg_db.fetch("""
        SELECT up.name, up.lat, up.lon FROM user_places up
        JOIN users u ON up.user_id = u.id WHERE u.device_id = $1
    """, device_id)


async def add_user_place(device_id: str, name: str, lat: float, lon: float) -> dict:
    user = await get_or_create_user(device_id)
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
    did = _did()
    folders = await pg_db.fetch(f"SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE device_id=$1 ORDER BY {order}", did)
    files = await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", recurrence, created_at, updated_at'
        f" FROM files WHERE type='note' AND archived=FALSE AND device_id=$1 ORDER BY {order}", did
    )
    for f in files:
        f["todo_total"], f["todo_done"] = _todo_stats(f.pop("content", None))

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
        "SELECT id, name, type, date, time, created_at, updated_at FROM files WHERE created_at::date = $1 AND device_id=$2 ORDER BY created_at DESC",
        target_date, _did(),
    )
    return rows


async def find_files_by_filter(f: dict, limit: int = 50) -> list[dict]:
    """通用文件查询（兼容旧接口，内部转为 SQL）。"""
    conditions: list[str] = ["device_id=$1"]
    params: list = [_did()]
    idx = 2

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
    conditions: list[str] = ["device_id=$1"]
    params: list = [_did()]
    idx = 2

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


async def list_appointments() -> list[dict]:
    """列出所有安排（按日期/时间排序）。"""
    return await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", recurrence, created_at, updated_at'
        ' FROM files WHERE type=$1 AND device_id=$2 ORDER BY date, "time"',
        "appointment", _did(),
    )


async def find_appointments_by_date(date: str) -> list[dict]:
    """列出某天的安排（按 time 排序）。"""
    target_date = datetime.strptime(date, "%Y-%m-%d").date()
    return await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", recurrence, created_at, updated_at'
        ' FROM files WHERE type=$1 AND date=$2 AND device_id=$3 ORDER BY "time"',
        "appointment", target_date, _did(),
    )


async def find_appointments_by_month(year: int, month: int) -> list[dict]:
    """列出某月有安排的日期及数量。"""
    prefix = f"{year:04d}-{month:02d}"
    rows = await pg_db.fetch(
        "SELECT date, COUNT(*) AS count FROM files WHERE type='appointment' AND date::text LIKE $1 AND device_id=$2 GROUP BY date ORDER BY date",
        f"{prefix}%", _did(),
    )
    return [{"date": r["date"].isoformat() if hasattr(r["date"], "isoformat") else str(r["date"]), "count": r["count"]} for r in rows]


async def list_alarms() -> list[dict]:
    """列出所有闹钟（按触发时间排序）。"""
    return await pg_db.fetch(
        'SELECT id, name, content, parent_id, type, date, "time", recurrence, created_at, updated_at'
        ' FROM files WHERE type=$1 AND device_id=$2 ORDER BY "time"',
        "alarm", _did(),
    )
