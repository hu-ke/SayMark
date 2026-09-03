"""归档路由：归档、恢复、归档列表。"""

from typing import List

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import ArchivedFileResponse, FileResponse, FileRestore

router = APIRouter(tags=["archive"])


@router.post("/api/files/{file_id}/archive", response_model=FileResponse)
async def archive_file(file_id: str):
    """归档文件（保留原文件夹引用与路径快照，移出文件夹）。"""
    try:
        result = await crud.archive_file(file_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="文件不存在")
    return result


@router.post("/api/files/{file_id}/restore", response_model=FileResponse)
async def restore_file(file_id: str, body: FileRestore):
    """恢复归档文件（缺省恢复原处；指定 target_folder_id 则移动到目标文件夹）。"""
    try:
        result = await crud.restore_file(file_id, body.target_folder_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="文件不存在")
    return result


@router.get("/api/archive", response_model=List[ArchivedFileResponse])
async def list_archived():
    """列出所有已归档文件（按归档时间倒序）。"""
    return await crud.list_archived_files()
