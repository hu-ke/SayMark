"""配置加载模块。

从 backend/.env 读取配置；必需变量缺失时启动报错并给出明确信息。
"""

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


# backend/.env 的绝对路径（本文件位于 backend/app/config.py）
_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    """应用配置。"""

    # DashScope（Qwen）API Key
    DASHSCOPE_API_KEY: str = Field(..., description="DashScope API Key")

    # PostgreSQL 连接配置
    PG_DSN: str = Field(..., description="PostgreSQL DSN，如 postgresql://user:pass@localhost:5432/saymark")

    # Qwen 模型配置
    QWEN_MODEL: str = Field(..., description="Qwen 模型名")
    QWEN_BASE_URL: str = Field(..., description="Qwen 兼容模式 base url")

    # Doubao Seed-ASR 2.0（语音识别，token 由用户后续提供）
    DOUBAO_ASR_API_KEY: str = Field("", description="新版控制台 X-Api-Key")
    DOUBAO_ASR_APP_KEY: str = Field("", description="旧版控制台 App ID（X-Api-App-Key）")
    DOUBAO_ASR_ACCESS_TOKEN: str = Field("", description="旧版控制台 Access Token（X-Api-Access-Key）")
    DOUBAO_ASR_RESOURCE_ID: str = Field("volc.seedasr.auc", description="豆包录音文件识别模型2.0资源ID")
    DOUBAO_ASR_BASE_URL: str = Field("https://openspeech.bytedance.com", description="火山引擎语音识别服务地址")
    DOUBAO_ASR_MODEL_NAME: str = Field("bigmodel", description="ASR 模型名称")

    # 阿里云 OSS（笔记图片存储，凭证由用户后续提供）
    ALIYUN_OSS_ACCESS_KEY_ID: str = Field("", description="阿里云 OSS AccessKey ID")
    ALIYUN_OSS_ACCESS_KEY_SECRET: str = Field("", description="阿里云 OSS AccessKey Secret")
    ALIYUN_OSS_BUCKET: str = Field("", description="阿里云 OSS Bucket 名称")
    ALIYUN_OSS_ENDPOINT: str = Field("", description="阿里云 OSS Endpoint，如 https://oss-cn-hangzhou.aliyuncs.com")
    ALIYUN_OSS_PUBLIC_BASE_URL: str = Field("", description="图片公开访问 base url，如 https://your-bucket.oss-cn-hangzhou.aliyuncs.com")

    model_config = SettingsConfigDict(
        env_file=str(_ENV_PATH),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    """获取配置单例。必需变量缺失时会抛出 ValidationError。"""
    return Settings()
