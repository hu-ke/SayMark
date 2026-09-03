"""FastAPI 入口。

启动时初始化 PostgreSQL、确保「未分类」目录；启用 CORS；挂载路由。
"""

from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from . import pg_ops
from .pg_db import close_pool
from .routers import ai, alarms, appointments, archive, asr, files, folders, geo, notes, reorder, upload, user


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期：启动时初始化资源，关闭时释放。"""
    await pg_ops.ensure_schema()
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


@app.middleware("http")
async def device_scope_middleware(request: Request, call_next):
    """从请求头读取设备标识，为数据访问层注入数据隔离上下文。"""
    did = request.headers.get("X-Device-ID", "") or ""
    pg_ops.set_device_id(did)
    try:
        if did:
            await pg_ops.claim_legacy_data(did)
        return await call_next(request)
    finally:
        pg_ops.set_device_id("")

# 所有业务路由统一挂在 /saymark-service 前缀下（配合部署/本机调试 baseURL）
service = APIRouter(prefix="/saymark-service")
service.include_router(folders.router)
service.include_router(files.router)
service.include_router(notes.router)
service.include_router(ai.router)
service.include_router(appointments.router)
service.include_router(alarms.router)
service.include_router(reorder.router)
service.include_router(geo.router)
service.include_router(user.router)
service.include_router(asr.router)
service.include_router(upload.router)
service.include_router(archive.router)
app.include_router(service)


@app.get("/")
async def root():
    """根路径返回简单状态 JSON。"""
    return {"status": "ok", "service": "SayMark API"}
