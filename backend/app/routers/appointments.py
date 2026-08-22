"""安排（Appointments）REST API —— 一次性日程，底层统一走 files（type=appointment）。"""

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import AppointmentCreate, AppointmentUpdate, FileResponse, MonthSummaryItem

router = APIRouter(prefix="/api/appointments", tags=["appointments"])


@router.get("", response_model=list[FileResponse])
async def list_appointments():
    """列出所有安排（按日期/时间排序）。"""
    return await crud.list_appointments()


@router.post("", response_model=FileResponse)
async def create_appointment(body: AppointmentCreate):
    """创建安排（一次性）。"""
    try:
        return await crud.create_file(
            name=body.name, content=body.content, parent_id=None,
            file_type="appointment", date=body.date, time=body.time,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.get("/date/{date}", response_model=list[FileResponse])
async def appointments_by_date(date: str):
    """列出某一天（YYYY-MM-DD）的所有安排。"""
    return await crud.find_appointments_by_date(date)


@router.get("/month/{year}/{month}", response_model=list[MonthSummaryItem])
async def appointments_by_month(year: int, month: int):
    """列出某月有安排的日期及数量（用于日历标记）。"""
    return await crud.find_appointments_by_month(year, month)


@router.get("/{appointment_id}", response_model=FileResponse)
async def get_appointment(appointment_id: str):
    """获取单个安排。"""
    doc = await crud.get_file(appointment_id)
    if doc is None or doc.get("type") != "appointment":
        raise HTTPException(404, "安排不存在")
    return doc


@router.patch("/{appointment_id}", response_model=FileResponse)
async def update_appointment(appointment_id: str, body: AppointmentUpdate):
    """更新安排（标题/日期/时间/内容）。"""
    updated = await crud.update_appointment(
        appointment_id,
        name=body.name, date=body.date, time=body.time, content=body.content,
    )
    if updated is None:
        raise HTTPException(404, "安排不存在")
    return updated


@router.delete("/{appointment_id}")
async def delete_appointment(appointment_id: str):
    """删除安排。"""
    doc = await crud.get_file(appointment_id)
    if doc is None:
        raise HTTPException(404, "安排不存在")
    await crud.delete_file(appointment_id)
    return {"success": True}
