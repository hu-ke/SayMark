"""Qwen 调用封装（基于 openai SDK 兼容模式）。

提供 async def chat(system_prompt, user_prompt, temperature) -> str。
"""

from functools import lru_cache
from typing import AsyncGenerator

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


async def chat_messages(messages: list[dict], temperature: float = 0.7) -> str:
    """非流式调用 Qwen，支持完整多轮对话消息列表。

    Args:
        messages: OpenAI 格式的消息列表 [{"role":"system"|"user"|"assistant", "content":"..."}]
        temperature: 采样温度
    """
    client = _get_client()
    settings = get_settings()
    response = await client.chat.completions.create(
        model=settings.QWEN_MODEL,
        messages=messages,
        temperature=temperature,
    )
    return response.choices[0].message.content or ""


async def chat_stream(
    messages: list[dict],
    temperature: float = 0.7,
) -> AsyncGenerator[str, None]:
    """流式调用 Qwen 模型，逐 token yield 文本。

    Args:
        messages: OpenAI 格式的消息列表 [{"role":"system"|"user"|"assistant", "content":"..."}]
        temperature: 采样温度
    """
    client = _get_client()
    settings = get_settings()
    stream = await client.chat.completions.create(
        model=settings.QWEN_MODEL,
        messages=messages,
        temperature=temperature,
        stream=True,
    )
    async for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content


async def embed(text: str) -> list[float]:
    """将文本转为向量（embedding），用于语义搜索。

    使用 DashScope text-embedding-v3 模型。
    返回 1024 维浮点数向量。
    """
    client = _get_client()
    response = await client.embeddings.create(
        model="text-embedding-v3",
        input=text,
    )
    return response.data[0].embedding
