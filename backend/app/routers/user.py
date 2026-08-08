"""用户 Profile REST API —— 管理用户位置与常用地点。"""

from fastapi import APIRouter, HTTPException

from .. import crud
from ..schemas import AddPlaceRequest, UpdateLocationRequest, UserProfileResponse

router = APIRouter(prefix="/api/user", tags=["user"])


@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(device_id: str = ""):
    """获取或创建用户 Profile。device_id 为空时自动生成。"""
    if not device_id.strip():
        # 自动生成一个设备 ID（简单用时间戳 + 随机）
        import uuid
        device_id = uuid.uuid4().hex[:16]
    return await crud.get_or_create_user(device_id)


@router.put("/location", response_model=UserProfileResponse)
async def update_location(device_id: str, body: UpdateLocationRequest):
    """更新用户当前位置。"""
    result = await crud.update_user_location(device_id, body.latitude, body.longitude)
    if result is None:
        raise HTTPException(404, "用户不存在，请先调用 GET /profile")
    return result


@router.post("/places", response_model=UserProfileResponse)
async def add_place(device_id: str, body: AddPlaceRequest):
    """添加/更新常用地点（同名覆盖）。"""
    result = await crud.add_user_place(device_id, body.name, body.lat, body.lon)
    if result is None:
        raise HTTPException(404, "用户不存在，请先调用 GET /profile")
    return result
