"""闹钟（Alarms）REST API —— 周期性提醒，底层统一走 files（type=alarm）。"""

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import AlarmCreate, AlarmUpdate, FileResponse

router = APIRouter(prefix="/api/alarms", tags=["alarms"])

_VALID_RECURRENCE = ("", "daily", "weekly", "monthly")


@router.get("", response_model=list[FileResponse])
async def list_alarms():
    """列出所有闹钟（按触发时间排序）。"""
    return await crud.list_alarms()


@router.post("", response_model=FileResponse)
async def create_alarm(body: AlarmCreate):
    """创建闹钟（周期性）。"""
    if body.recurrence not in _VALID_RECURRENCE:
        raise HTTPException(status_code=422, detail=f"recurrence 无效：{body.recurrence}")
    try:
        return await crud.create_file(
            name=body.name, content=body.content, parent_id=None,
            file_type="alarm", time=body.time, recurrence=body.recurrence,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.get("/{alarm_id}", response_model=FileResponse)
async def get_alarm(alarm_id: str):
    """获取单个闹钟。"""
    doc = await crud.get_file(alarm_id)
    if doc is None or doc.get("type") != "alarm":
        raise HTTPException(404, "闹钟不存在")
    return doc


@router.patch("/{alarm_id}", response_model=FileResponse)
async def update_alarm(alarm_id: str, body: AlarmUpdate):
    """更新闹钟（标题/时间/周期/内容）。"""
    if body.recurrence is not None and body.recurrence not in _VALID_RECURRENCE:
        raise HTTPException(status_code=422, detail=f"recurrence 无效：{body.recurrence}")
    updated = await crud.update_alarm(
        alarm_id,
        name=body.name, time=body.time, recurrence=body.recurrence, content=body.content,
    )
    if updated is None:
        raise HTTPException(404, "闹钟不存在")
    return updated


@router.delete("/{alarm_id}")
async def delete_alarm(alarm_id: str):
    """删除闹钟。"""
    doc = await crud.get_file(alarm_id)
    if doc is None:
        raise HTTPException(404, "闹钟不存在")
    await crud.delete_file(alarm_id)
    return {"success": True}
