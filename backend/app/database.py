"""motor 异步 MongoDB 客户端。

导入时不连接 MongoDB，仅在运行时按需连接（app 启动时连接）。
"""

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

from .config import get_settings

# 全局客户端与数据库句柄；在 main.py 的 lifespan 中初始化
client: AsyncIOMotorClient = None  # type: ignore[assignment]
db: AsyncIOMotorDatabase = None  # type: ignore[assignment]


def get_db() -> AsyncIOMotorDatabase:
    """获取数据库句柄。若未初始化，抛出明确错误。"""
    if db is None:
        raise RuntimeError("数据库尚未初始化，请检查应用启动流程。")
    return db


async def connect_db() -> None:
    """连接 MongoDB 并初始化全局 db 句柄。"""
    global client, db
    settings = get_settings()
    client = AsyncIOMotorClient(settings.MONGO_URI)
    db = client[settings.MONGO_DB_NAME]


async def ensure_indexes() -> None:
    """创建 folders / files 的 (parent_id, name) 索引。"""
    if db is None:
        raise RuntimeError("数据库尚未初始化。")
    await db.folders.create_index([("parent_id", 1), ("name", 1)])
    await db.files.create_index([("parent_id", 1), ("name", 1)])


async def close_db() -> None:
    """关闭 MongoDB 连接。"""
    global client, db
    if client is not None:
        client.close()
    client = None  # type: ignore[assignment]
    db = None  # type: ignore[assignment]
