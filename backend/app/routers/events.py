"""日程（Events）REST API —— 底层统一走 files collection（type=event）。"""

from pydantic import BaseModel

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import FileResponse, MonthSummaryItem

router = APIRouter(prefix="/api/events", tags=["events"])


class EventCreateRequest(BaseModel):
    title: str
    date: str          # YYYY-MM-DD
    time: str = ""     # HH:MM 或空
    content: str = ""
    target_folder_id: str = ""  # 缺省存入"未分类"


@router.post("", response_model=FileResponse)
async def create_event(body: EventCreateRequest):
    """创建日程（即 type=event 的文件）。"""
    # 确定目标文件夹
    if body.target_folder_id:
        f = await crud.get_folder(body.target_folder_id)
        if f is not None:
            folder_id = f["id"]
        else:
            uncategorized = await crud.get_default_uncategorized_folder()
            folder_id = uncategorized["id"]
    else:
        uncategorized = await crud.get_default_uncategorized_folder()
        folder_id = uncategorized["id"]

    markdown = body.content or f"# {body.title}\n- 日期：{body.date}\n" + (
        f"- 时间：{body.time}\n" if body.time else ""
    )
    file_doc = await crud.create_file(
        name=body.title, content=markdown, parent_id=folder_id,
        file_type="event", date=body.date, time=body.time,
    )
    return file_doc


@router.get("/{event_id}", response_model=FileResponse)
async def get_event(event_id: str):
    """获取单个日程（即文件）。"""
    file_doc = await crud.get_file(event_id)
    if file_doc is None or file_doc.get("type") != "event":
        raise HTTPException(404, "日程不存在")
    return file_doc


@router.get("/date/{date}", response_model=list[FileResponse])
async def events_by_date(date: str):
    """列出某一天（YYYY-MM-DD）的所有日程。"""
    return await crud.find_files_by_date(date)


@router.get("/month/{year}/{month}", response_model=list[MonthSummaryItem])
async def events_by_month(year: int, month: int):
    """列出某月有日程的日期及数量（用于日历标记）。"""
    return await crud.find_files_by_month(year, month)


@router.delete("/{event_id}")
async def delete_event(event_id: str):
    """删除日程（即删除对应的文件）。"""
    file_doc = await crud.get_file(event_id)
    if file_doc is None:
        raise HTTPException(404, "日程不存在")
    await crud.delete_file(event_id)
    return {"success": True}


@router.patch("/{event_id}", response_model=FileResponse)
async def update_event(event_id: str, content: str = ""):
    """更新日程内容。"""
    updated = await crud.update_file_content(event_id, content)
    if updated is None:
        raise HTTPException(404, "日程不存在")
    return updated
