"""文件路由：获取、创建、重命名/改内容、移动、删除。"""

from fastapi import APIRouter, HTTPException

from .. import crud
from ..schemas import FileCreate, FileMove, FileResponse, FileUpdate

router = APIRouter(prefix="/api/files", tags=["files"])


@router.get("/{file_id}", response_model=FileResponse)
async def get_file(file_id: str):
    """返回文件（含 content）。"""
    try:
        file = await crud.get_file(file_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if file is None:
        raise HTTPException(status_code=404, detail="文件不存在")
    return file


@router.post("", response_model=FileResponse)
async def create_file(body: FileCreate):
    """创建文件。"""
    try:
        return await crud.create_file(body.name, body.content, body.parent_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.patch("/{file_id}", response_model=FileResponse)
async def update_file(file_id: str, body: FileUpdate):
    """重命名/改内容（name 与 content 至少提供一个，可同时提供）。"""
    if body.name is None and body.content is None:
        raise HTTPException(status_code=422, detail="至少提供 name 或 content")
    try:
        result = None
        if body.name is not None:
            result = await crud.update_file_name(file_id, body.name)
            if result is None:
                raise HTTPException(status_code=404, detail="文件不存在")
        if body.content is not None:
            result = await crud.update_file_content(file_id, body.content)
            if result is None:
                raise HTTPException(status_code=404, detail="文件不存在")
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    return result


@router.put("/{file_id}/move", response_model=FileResponse)
async def move_file(file_id: str, body: FileMove):
    """移动文件到目标文件夹。"""
    try:
        result = await crud.move_file(file_id, body.target_folder_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="文件不存在")
    return result


@router.delete("/{file_id}")
async def delete_file(file_id: str):
    """删除文件。"""
    try:
        deleted = await crud.delete_file(file_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if not deleted:
        raise HTTPException(status_code=404, detail="文件不存在")
    return {"success": True}
