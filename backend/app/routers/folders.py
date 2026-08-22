"""文件夹路由：目录树、创建、重命名、递归删除。"""

from typing import List

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import FolderCreate, FolderResponse, FolderTreeNode, FolderUpdate

router = APIRouter(prefix="/api/folders", tags=["folders"])


@router.get("/tree", response_model=List[FolderTreeNode])
async def get_tree():
    """返回完整目录树（含 files）。"""
    return await crud.get_folder_tree()


@router.post("", response_model=FolderResponse)
async def create_folder(body: FolderCreate):
    """创建文件夹（parent_id 缺省为顶级）。"""
    try:
        return await crud.create_folder(body.name, body.parent_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.patch("/{folder_id}", response_model=FolderResponse)
async def rename_folder(folder_id: str, body: FolderUpdate):
    """重命名文件夹。"""
    try:
        result = await crud.update_folder_name(folder_id, body.name)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="文件夹不存在")
    return result


@router.delete("/{folder_id}")
async def delete_folder(folder_id: str):
    """递归删除文件夹。"""
    try:
        deleted = await crud.delete_folder(folder_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if not deleted:
        raise HTTPException(status_code=404, detail="文件夹不存在")
    return {"success": True}
