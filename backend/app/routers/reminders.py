"""提醒（Reminders）REST API —— 列出/管理设置了提醒的日程。"""

from fastapi import APIRouter, HTTPException

from .. import crud
from ..schemas import FileResponse

router = APIRouter(prefix="/api/reminders", tags=["reminders"])


@router.get("", response_model=list[FileResponse])
async def list_reminders():
    """列出所有设置了提醒的日程（按日期排序）。"""
    return await crud.find_files_with_reminders()


@router.patch("/{file_id}", response_model=FileResponse)
async def cancel_reminder(file_id: str):
    """取消某个日程的提醒（设为 0 即取消）。"""
    updated = await crud.set_reminder(file_id, 0)
    if updated is None:
        raise HTTPException(404, "文件不存在")
    return updated
