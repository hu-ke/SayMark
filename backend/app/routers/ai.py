"""AI 指令路由：自然语言 -> 结构化 JSON -> 执行。"""

import json

from fastapi import APIRouter

from ..schemas import CommandRequest, CommandResult
from ..services import command_executor, command_parser

router = APIRouter(prefix="/api/ai", tags=["ai"])


@router.post("/command", response_model=CommandResult)
async def command(body: CommandRequest):
    """解析自然语言指令为 JSON 并执行，返回统一结果对象。"""
    # 1. 解析为结构化 JSON
    try:
        parsed = await command_parser.parse_command(body.text)
    except json.JSONDecodeError:
        return CommandResult(
            action="unknown",
            success=False,
            message="指令解析失败：无法识别为有效 JSON",
        )
    except Exception as e:  # 网络或模型异常
        return CommandResult(
            action="unknown",
            success=False,
            message=f"指令解析失败：{e}",
        )
    # 2. 执行（executor 内部已兜底异常，不会抛 500）
    result = await command_executor.execute(parsed)
    return result
