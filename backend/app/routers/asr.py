"""ASR 路由：接收音频，上传 OSS 后调用 Doubao Seed-ASR 2.0 返回识别文本。"""

import asyncio
import base64

from fastapi import APIRouter, HTTPException
from loguru import logger
from pydantic import BaseModel

from ..services import asr, oss

router = APIRouter(prefix="/api/asr", tags=["asr"])


class RecognizeRequest(BaseModel):
    audio_base64: str
    format: str = "wav"
    sample_rate: int = 16000


@router.post("/recognize")
async def recognize(body: RecognizeRequest):
    """将 base64 音频转写为文本。

    音频先上传到 OSS（公开可访问），再把 OSS URL 交给豆包录音文件识别。
    """
    try:
        raw = base64.b64decode(body.audio_base64)
    except Exception:
        raise HTTPException(status_code=422, detail="audio_base64 解码失败")
    if not raw:
        raise HTTPException(status_code=422, detail="音频为空")

    try:
        audio_url = await asyncio.to_thread(oss.upload_audio, raw, body.format)
        text = await asr.transcribe(audio_url, body.format, body.sample_rate)
        return {"transcript": text}
    except oss.OSSNotConfigured as e:
        logger.error(f"ASR 上传音频失败（OSS 未配置）: {e}")
        raise HTTPException(status_code=503, detail=str(e))
    except asr.ASRNotConfigured as e:
        logger.error(f"ASR 鉴权未配置: {e}")
        raise HTTPException(status_code=503, detail=str(e))
    except asr.ASRError as e:
        logger.error(f"ASR 识别失败: {e}")
        raise HTTPException(status_code=502, detail=str(e))
