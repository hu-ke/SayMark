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
