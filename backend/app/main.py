"""FastAPI 入口。

启动时初始化 PostgreSQL、确保「未分类」目录；启用 CORS；挂载路由。
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import pg_ops
from .pg_db import close_pool
from .routers import ai, events, files, folders, geo, notes, reminders, reorder, user


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期：启动时初始化资源，关闭时释放。"""
    await pg_ops.ensure_schema()
    await pg_ops.get_default_uncategorized_folder()
    yield
    await close_pool()


app = FastAPI(title="SayMark API", lifespan=lifespan)

# 启用 CORS（开发用，允许所有来源/方法/头）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 挂载路由
app.include_router(folders.router)
app.include_router(files.router)
app.include_router(notes.router)
app.include_router(ai.router)
app.include_router(events.router)
app.include_router(reminders.router)
app.include_router(reorder.router)
app.include_router(geo.router)
app.include_router(user.router)


@app.get("/")
async def root():
    """根路径返回简单状态 JSON。"""
    return {"status": "ok", "service": "SayMark API"}
