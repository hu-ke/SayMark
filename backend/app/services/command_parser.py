"""自然语言 -> 结构化 JSON 指令解析器。"""

import json
import re

from . import qwen

# 指令解析系统提示词
SYSTEM_PROMPT = (
    "你是语音指令解析器。把用户的自然语言指令解析为严格的 JSON。支持的 action：\n"
    "- create_note: 创建笔记。参数 content(备忘原文), target_folder?(可选目录名)\n"
    "- create_folder: 创建文件夹。参数 name, parent_folder?(可选父目录名，缺省顶级)\n"
    "- rename: 重命名。参数 type(file|folder), old_name, new_name, parent_folder?(定位用)\n"
    "- delete: 删除。参数 type(file|folder), name, parent_folder?(定位用)\n"
    "- move_file: 移动文件。参数 file_name, from_folder, to_folder\n"
    "- locate_folder: 定位文件夹。参数 folder_name\n"
    "- list: 列出内容。参数 path?(可选目录名，缺省根)\n"
    "当用户口述的是备忘内容而非指令时，返回 create_note。\n"
    "只输出 JSON 对象，不要 markdown 代码块，不要解释。"
    '示例输入"把工作目录里的周会笔记移到归档目录" -> '
    '{"action":"move_file","file_name":"周会笔记","from_folder":"工作","to_folder":"归档"}。'
)


def _strip_code_fence(text: str) -> str:
    """去除可能的 ```json ... ``` 代码块包裹。"""
    text = text.strip()
    # 匹配 ```json ... ``` 或 ``` ... ```
    fence_pattern = re.compile(r"^```(?:json)?\s*(.*?)\s*```$", re.DOTALL | re.IGNORECASE)
    match = fence_pattern.match(text)
    if match:
        return match.group(1).strip()
    # 兜底：去掉首尾可能残留的反引号
    if text.startswith("```"):
        text = text.lstrip("`")
        # 去掉可能的 json 标记
        text = re.sub(r"^(json)?\s*", "", text, flags=re.IGNORECASE)
    if text.endswith("```"):
        text = text.rstrip("`")
    return text.strip()


async def parse_command(text: str) -> dict:
    """把用户指令文本解析为结构化 JSON 对象。

    Raises:
        json.JSONDecodeError: 模型输出无法解析为 JSON 时抛出。
    """
    raw = await qwen.chat(SYSTEM_PROMPT, text, temperature=0.1)
    cleaned = _strip_code_fence(raw)
    return json.loads(cleaned)
