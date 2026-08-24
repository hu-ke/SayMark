"""Doubao Seed-ASR 2.0（录音文件识别标准版）封装。

流程：提交音频链接 -> 轮询查询结果 -> 返回识别文本。
鉴权与资源 ID 从 backend/.env 读取，密钥由用户后续提供。
"""

import asyncio
import uuid

import httpx

from ..config import get_settings


class ASRNotConfigured(Exception):
    """ASR 未配置密钥。"""


class ASRError(Exception):
    """ASR 调用失败。"""


def _headers() -> dict[str, str]:
    """构造火山引擎语音识别鉴权头（新版 X-Api-Key 优先，兼容旧版 App Key + Token）。"""
    s = get_settings()
    headers = {
        "X-Api-Resource-Id": s.DOUBAO_ASR_RESOURCE_ID,
        "X-Api-Request-Id": str(uuid.uuid4()),
        "X-Api-Sequence": "-1",
        "Content-Type": "application/json",
    }
    if s.DOUBAO_ASR_API_KEY:
        headers["X-Api-Key"] = s.DOUBAO_ASR_API_KEY
    elif s.DOUBAO_ASR_APP_KEY and s.DOUBAO_ASR_ACCESS_TOKEN:
        headers["X-Api-App-Key"] = s.DOUBAO_ASR_APP_KEY
        headers["X-Api-Access-Key"] = s.DOUBAO_ASR_ACCESS_TOKEN
    else:
        raise ASRNotConfigured(
            "Doubao ASR 未配置：请在 backend/.env 填写 DOUBAO_ASR_API_KEY "
            "（或 DOUBAO_ASR_APP_KEY + DOUBAO_ASR_ACCESS_TOKEN）"
        )
    return headers


async def _submit(audio_url: str, audio_format: str, sample_rate: int) -> str:
    """提交音频链接，返回任务 ID（即本次请求的 X-Api-Request-Id）。"""
    s = get_settings()
    body = {
        "user": {"uid": s.DOUBAO_ASR_API_KEY or s.DOUBAO_ASR_APP_KEY},
        "audio": {
            "url": audio_url,
            "format": audio_format,
            "codec": "raw",
            "rate": sample_rate,
            "bits": 16,
            "channel": 1,
        },
        "request": {
            "model_name": s.DOUBAO_ASR_MODEL_NAME,
            "enable_itn": True,
            "enable_punc": True,
        },
    }
    headers = _headers()
    task_id = headers["X-Api-Request-Id"]
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{s.DOUBAO_ASR_BASE_URL}/api/v3/auc/bigmodel/submit",
            headers=headers,
            json=body,
        )
    if resp.status_code != 200:
        raise ASRError(f"ASR 提交失败：HTTP {resp.status_code} {resp.text[:200]}")
    return task_id


async def _query(task_id: str) -> tuple[str, dict]:
    """查询识别结果，返回 (X-Api-Status-Code, body)。"""
    s = get_settings()
    headers = _headers()
    headers["X-Api-Request-Id"] = task_id
    headers.pop("X-Api-Sequence", None)
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{s.DOUBAO_ASR_BASE_URL}/api/v3/auc/bigmodel/query",
            headers=headers,
            json={},
        )
    if resp.status_code != 200:
        raise ASRError(f"ASR 查询失败：HTTP {resp.status_code} {resp.text[:200]}")
    status_code = resp.headers.get("X-Api-Status-Code", "20000000")
    try:
        body = resp.json()
    except Exception:
        body = {}
    return status_code, body


async def transcribe(audio_url: str, audio_format: str = "wav", sample_rate: int = 16000) -> str:
    """识别音频并返回文本。

    Raises:
        ASRNotConfigured: 未配置密钥。
        ASRError: 调用失败或超时。
    """
    task_id = await _submit(audio_url, audio_format, sample_rate)

    for _ in range(120):  # 最多轮询约 60 秒
        status_code, body = await _query(task_id)
        if status_code == "20000000":
            result = body.get("result") or {}
            return (result.get("text") or "").strip()
        if status_code == "20000003":  # 静音音频
            return ""
        # 20000001 处理中 / 20000002 队列中 → 继续轮询
        if status_code not in ("20000001", "20000002"):
            raise ASRError(f"ASR 识别失败：状态码 {status_code}")
        await asyncio.sleep(0.5)

    raise ASRError("ASR 识别超时")
