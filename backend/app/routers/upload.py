"""上传路由：图片上传到阿里云 OSS。"""

import base64

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import oss

router = APIRouter(prefix="/api/upload", tags=["upload"])


class UploadImageRequest(BaseModel):
    image_base64: str


@router.post("/image")
async def upload_image(body: UploadImageRequest):
    """接收 base64 图片，上传到 OSS 并返回公开访问 URL。"""
    try:
        raw = base64.b64decode(body.image_base64)
    except Exception:
        raise HTTPException(status_code=422, detail="image_base64 解码失败")
    if not raw:
        raise HTTPException(status_code=422, detail="图片为空")
    if len(raw) > 20 * 1024 * 1024:
        raise HTTPException(status_code=422, detail="图片过大（超过 20MB）")

    try:
        url = oss.upload_image(raw)
        return {"url": url}
    except oss.OSSNotConfigured as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"图片上传失败：{e}")
