"""语音转录 -> markdown 笔记生成器。"""

from datetime import datetime

from . import qwen

# 笔记生成系统提示词
SYSTEM_PROMPT = (
    "你是笔记整理助手。根据用户口述内容生成一份简洁的 markdown 笔记。"
    "第一行必须是 # 开头的标题（概括内容），"
    "后面用要点列出关键信息（时间、地点、事项等）。"
    "只输出 markdown 正文，不要额外解释。"
)


def extract_title(markdown: str) -> str:
    """从 markdown 第一行提取标题。

    取第一行去掉 # 与首尾空白作为标题/文件名；
    若无标题（非 # 开头或空）则返回空字符串。
    """
    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            # 去掉前导 # 与空白
            return stripped.lstrip("#").strip()
        # 第一个非空行不是标题
        break
    return ""


def default_title() -> str:
    """无标题时使用的默认文件名（时间戳）。"""
    return "笔记_" + datetime.now().strftime("%Y%m%d_%H%M%S")


async def generate_note(transcript: str) -> str:
    """根据转录文本生成 markdown 笔记，返回完整 markdown 字符串。"""
    user_prompt = transcript
    markdown = await qwen.chat(SYSTEM_PROMPT, user_prompt, temperature=0.7)
    return markdown.strip()


async def generate_note_with_title(transcript: str) -> tuple[str, str]:
    """生成笔记并提取标题。

    Returns:
        (title, markdown)：title 为文件名，markdown 为完整内容。
        若提取不到标题，title 使用时间戳默认值。
    """
    markdown = await generate_note(transcript)
    title = extract_title(markdown)
    if not title:
        title = default_title()
    return title, markdown


# 笔记合并系统提示词（补充内容到已有笔记）
MERGE_SYSTEM_PROMPT = (
    "你是笔记整理助手。下面给出一份已有的 markdown 笔记和用户想补充的新内容。"
    "请把新内容合并进笔记，保留原有内容不丢失，保持 markdown 格式与标题。"
    "如果新内容与已有条目重复，可合并；如果是新的时间/事项，按合理顺序插入。"
    "只输出更新后的完整 markdown，不要解释。"
)


async def merge_note(existing_markdown: str, new_content: str) -> str:
    """把新内容合并到已有 markdown 笔记，返回更新后的完整 markdown。"""
    user_prompt = f"已有笔记：\n{existing_markdown}\n\n补充内容：\n{new_content}"
    markdown = await qwen.chat(MERGE_SYSTEM_PROMPT, user_prompt, temperature=0.7)
    return markdown.strip()
