"""Qwen 调用封装（基于 openai SDK 兼容模式）。

提供 async def chat(system_prompt, user_prompt, temperature) -> str。
"""

from functools import lru_cache

from openai import AsyncOpenAI

from ..config import get_settings


@lru_cache
def _get_client() -> AsyncOpenAI:
    """获取异步 OpenAI 兼容客户端（单例）。"""
    settings = get_settings()
    return AsyncOpenAI(
        api_key=settings.DASHSCOPE_API_KEY,
        base_url=settings.QWEN_BASE_URL,
    )


async def chat(system_prompt: str, user_prompt: str, temperature: float = 0.7) -> str:
    """调用 Qwen 模型，返回纯文本响应。

    Args:
        system_prompt: 系统提示词
        user_prompt: 用户输入文本
        temperature: 采样温度；笔记生成建议 0.7，指令解析建议 0.1
    """
    client = _get_client()
    settings = get_settings()
    response = await client.chat.completions.create(
        model=settings.QWEN_MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=temperature,
    )
    return response.choices[0].message.content or ""
