"""阿里云 OSS 上传封装。

笔记图片、语音识别音频都通过后端中转上传到 OSS，返回公开访问 URL。
凭证从 backend/.env 读取。
"""

import uuid

from ..config import get_settings


class OSSNotConfigured(Exception):
    """OSS 未配置。"""


def _bucket():
    try:
        import oss2
    except ImportError:
        raise OSSNotConfigured("缺少 oss2 依赖，请运行 pip install -r requirements.txt")

    s = get_settings()
    if not (
        s.ALIYUN_OSS_ACCESS_KEY_ID
        and s.ALIYUN_OSS_ACCESS_KEY_SECRET
        and s.ALIYUN_OSS_BUCKET
        and s.ALIYUN_OSS_ENDPOINT
    ):
        raise OSSNotConfigured(
            "阿里云 OSS 未配置：请在 backend/.env 填写 ALIYUN_OSS_ACCESS_KEY_ID / "
            "ALIYUN_OSS_ACCESS_KEY_SECRET / ALIYUN_OSS_BUCKET / ALIYUN_OSS_ENDPOINT"
        )
    auth = oss2.Auth(s.ALIYUN_OSS_ACCESS_KEY_ID, s.ALIYUN_OSS_ACCESS_KEY_SECRET)
    return oss2.Bucket(auth, s.ALIYUN_OSS_ENDPOINT, s.ALIYUN_OSS_BUCKET)


def _detect_meta(data: bytes) -> tuple[str, str]:
    """根据文件头判断图片扩展名与 Content-Type。"""
    if data.startswith(b"\xff\xd8"):
        return "jpg", "image/jpeg"
    if data.startswith(b"\x89PNG"):
        return "png", "image/png"
    if data[:4] == b"GIF8":
        return "gif", "image/gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp", "image/webp"
    return "jpg", "image/jpeg"


def upload(data: bytes, key_prefix: str, ext: str, content_type: str) -> str:
    """上传字节到 OSS，返回公开访问 URL。"""
    s = get_settings()
    if not s.ALIYUN_OSS_PUBLIC_BASE_URL:
        raise OSSNotConfigured("公开地址未配置：请设置 ALIYUN_OSS_PUBLIC_BASE_URL")

    bucket = _bucket()
    key = f"{key_prefix}/{uuid.uuid4().hex}.{ext}"
    bucket.put_object(key, data, headers={"Content-Type": content_type})
    return f"{s.ALIYUN_OSS_PUBLIC_BASE_URL.rstrip('/')}/{key}"


def upload_image(data: bytes) -> str:
    """上传笔记图片到 OSS。"""
    ext, content_type = _detect_meta(data)
    return upload(data, "notes", ext, content_type)


def upload_audio(data: bytes, audio_format: str = "wav") -> str:
    """上传语音识别音频到 OSS。"""
    return upload(data, "audio", audio_format, "audio/wav")
