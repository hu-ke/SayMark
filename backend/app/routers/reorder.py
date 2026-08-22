"""排序接口：交换两个同层级项的位置。"""

from fastapi import APIRouter, HTTPException

from .. import pg_ops as crud
from ..schemas import ReorderRequest

router = APIRouter(prefix="/api/reorder", tags=["reorder"])


@router.put("")
async def reorder(body: ReorderRequest):
    """交换 source_id 与 target_id 的位置（两者必须同类型且同父级）。"""
    try:
        ok = await crud.swap_item_positions(body.type, body.source_id, body.target_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if not ok:
        raise HTTPException(status_code=404, detail="目标项不存在")
    return {"success": True}
