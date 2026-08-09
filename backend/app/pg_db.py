"""PostgreSQL 连接池（基于 asyncpg）。"""

from datetime import date, datetime, time
from functools import lru_cache

import asyncpg

from .config import get_settings

_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    """获取连接池单例（惰性初始化）。"""
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = await asyncpg.create_pool(
            dsn=settings.PG_DSN,
            min_size=2,
            max_size=10,
            statement_cache_size=0,
        )
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def _serialize(row: dict) -> dict:
    """将 PG 原生类型转为 JSON 兼容类型（id→str, datetime→ISO, None→'' for date fields）。"""
    str_fields = {"date", "time", "recurrence_end_date"}
    for k, v in row.items():
        if (k == "id" or k.endswith("_id")) and v is not None:
            row[k] = str(v)
        elif isinstance(v, datetime):
            row[k] = v.isoformat()
        elif isinstance(v, date):
            row[k] = v.isoformat()
        elif isinstance(v, time):
            row[k] = v.isoformat()
        elif v is None and k in str_fields:
            row[k] = ""
    return row


async def fetch(query: str, *args) -> list[dict]:
    """执行查询，返回 JSON 兼容的 dict 列表。"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *args)
        return [_serialize(dict(r)) for r in rows]


async def fetchrow(query: str, *args) -> dict | None:
    """执行查询，返回 JSON 兼容的单行 dict 或 None。"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, *args)
        return _serialize(dict(row)) if row else None


async def fetch_raw(query: str, *args) -> list[dict]:
    """执行查询，返回原始类型 dict 列表（内部使用）。"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *args)
        return [dict(r) for r in rows]


async def fetchrow_raw(query: str, *args) -> dict | None:
    """执行查询，返回原始类型单行 dict 或 None（内部使用）。"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, *args)
        return dict(row) if row else None


async def execute(query: str, *args) -> str:
    """执行 INSERT/UPDATE/DELETE，返回 "INSERT <id>" 或 "UPDATE <count>" 或 "DELETE <count>"。"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        if query.strip().upper().startswith("INSERT"):
            row = await conn.fetchrow(query, *args)
            last_id = None
            for v in (row or {}).values():
                last_id = v
                break
            return f"INSERT {last_id}" if last_id is not None else "INSERT 1"
        else:
            result = await conn.execute(query, *args)
            count = result.split()[-1] if result else "0"
            action = query.strip().upper().split()[0]
            return f"{action} {count}"
