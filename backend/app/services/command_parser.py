"""自然语言 -> 结构化 JSON 指令解析器。

解析时把当前真实目录树喂给 LLM，由 LLM 根据语义直接选出要操作的文件/文件夹 id，
而非依赖字符串模糊匹配。支持多步骤指令与「补充笔记」。

输出格式：{"steps": [...], "needs_confirmation": bool, "summary": str}
"""

import json
import re
from datetime import datetime

from .. import crud
from . import qwen

# 指令解析系统提示词（运行时拼接目录树清单）
_SYSTEM_PROMPT_TEMPLATE = (
    "你是语音指令解析器。根据用户指令和当前目录树，输出严格的 JSON 对象。\n\n"
    "现在时间是：{now}\n"
    "当前目录树（每行：类型 | id | 名称 | 创建时间 | 完整路径）：\n"
    "{inventory}\n\n"
    "{target_context}"
    "支持的 action：\n"
    "- create_note: 新建笔记（无明确时间/日期的备忘）。参数 content(备忘原文), target_folder_id?(可选目录 id；缺省「未分类」), target_folder?(用户提到的目录名，兜底用)\n"
    "- create_event: 新建日程（有明确时间/日期的安排）。参数 title(日程标题), date(日期 YYYY-MM-DD), time(时间 HH:MM，缺省空), content(日程详情), target_folder_id?(可选目录 id), target_folder?(用户提到的目录名，兜底用)。当用户说「安排/预定/约了/XX点XX分/下周一/明天/X月X号」并且涉及具体时间点时用此 action\n"
    "- append_note: 补充/追加内容到已有笔记或日程。参数 target_id(要补充的文件 id), name(用户提到的文件名，兜底用), content(要补充的新内容)。当用户说「补充/加上/添加到XX」时用此 action\n"
    "- set_reminder: 为日程设置提醒。参数 target_id(日程文件 id), name(日程名称，兜底用), minutes(提前多少分钟提醒，0=取消提醒), recurrence(周期：空=一次性, daily=每天, weekly=每周, monthly=每月), recurrence_end_date(周期结束日期 YYYY-MM-DD，如「到10月第一周」需换算为该周周一的日期)。当用户说「提前XX分钟提醒」「每天提醒」「每周X提醒」「到X月X号为止」时用此 action\n"
    "- save_place: 保存用户提到的地点到个人地名库。参数 name(地名), lat(纬度数字), lon(经度数字)。当用户说「我在XX」「我家在XX」且你想记住这个地点时用此 action。注意：地名不知道坐标的话凭知识估算大致坐标。\n"
    "- create_folder: 创建文件夹。参数 name, parent_folder_id?(可选父目录 id，缺省顶级), parent_folder?(用户提到的父目录名，兜底用)\n"
    "- rename: 重命名。参数 type(file|folder), target_id(要改的项的 id；找不到留空\"\"), name(用户提到的原名，兜底用), new_name\n"
    "- delete: 删除。参数 type(file|folder), target_id(要删的项的 id；找不到留空\"\"), name(用户提到的名称，兜底用)\n"
    "- move_file: 移动文件。参数 file_id(要移动的文件 id；找不到留空\"\"), file_name(用户提到的文件名，兜底用), to_folder_id(目标目录 id；找不到留空\"\"), to_folder(用户提到的目标目录名，兜底用)\n"
    "- locate_folder: 定位文件夹。参数 target_id(文件夹 id；找不到留空\"\"), name(用户提到的名称，兜底用)\n"
    "- list: 列出内容。参数 target_folder_id?(可选目录 id；找不到留空\"\"), path(用户提到的目录名，兜底用；缺省根)\n\n"
    "输出格式（JSON 对象）：\n"
    '{{"steps": [<action 对象, ...>], "needs_confirmation": <true|false>, "summary": "<用一句话概括计划做什么>"}}\n\n'
    "特殊输入格式：当用户消息包含「[上轮AI回复] ... [用户指令] ...」时，说明用户在与 AI 对话中跟进。"
    "此时「[上轮AI回复]」是 AI 上一轮说的内容（含建议/提醒等），「[用户指令]」是用户当前说的话。"
    "你需要从 AI 回复中提取相关内容作为操作的 content，根据指令中的目标（日程/笔记名）在目录树中找到对应项，"
    "用 append_note 或 set_reminder 去更新它，不要新建。\n"
    "例：[上轮AI回复] 别忘了带球拍、水壶、毛巾哦 [用户指令] 把这些提醒加到刚才的日程里 → 目录树中找「打球」→ append_note(target_id=xxx, content='别忘了携带球拍、水壶、毛巾哦')\n\n"
    "规则：\n"
    "1. 操作已存在的文件/文件夹时，必须从目录树中根据语义找到用户所指的项，填入其真实 id。\n"
    "2. 用户口述的名称可能与树中名称不完全一致（如省略、别名、多字少字），请根据语义判断最匹配的项。\n"
    "3. 若目录树中确实没有匹配项，对应 id 留空字符串 \"\"，并把你听到的名称填到对应 name 字段。\n"
    "4. **区分笔记与日程**：用户提到具体的未来时间点（如下周一下午2点、明天3点、8月15号晚上），则意图是「建日程」→ 用 create_event。用户只是记东西、没有具体时间（如「记一件好玩的事」「今天买了菜」），则意图是「记笔记」→ 用 create_note。\n"
    "\n"
    "相对时间换算规则（严格按此换算，不要多算！）：\n"
    "- 「今天」= 当前日期\n"
    "- 「明天」= 当前日期 + 1 天\n"
    "- 「后天」= 当前日期 + 2 天\n"
    "- 「大后天」= 当前日期 + 3 天\n"
    "- 「下周X」：先找当前日期之后的下一个周X（跳过当前周），得到 date。例：今天是周五，「下周周一」= 下下周一（跳过本周六日，找下周一）。再强调一遍：「下周X」只跳一次，不是两周！\n"
    "- 「下下周X」：先找到下周X，再加 7 天。例：今天是周五（周5），「下下周周六」：下周周六 = 当天+8 天，下下周周六 = 当天+15 天。\n"
    "- 「上/昨/前」同理反向推算\n"
    "- 「X月X号/X月X日」直接取该日期，年份取当前年份（如果该日期已过，取明年）\n"
    "- 如果有具体时间（如「下午2点」），填入 time 字段（24小时制 HH:MM）\n"
    "- 计算得出的 date 必须填入 YYYY-MM-DD 格式，不要算错！\n"
    "5. **补充/跟进已有事项**：当用户对刚刚讨论或创建的事项补充信息时（如「提前30分钟和我说」「地点是XX」「备注一下」），必须在目录树中找到该事项（按名称语义匹配），用 append_note 补充内容或用 set_reminder 设置提醒，**不要**新建！判断标准：用户没有新的时间点关键词（下周一、明天等），且提到的是已经存在的东西，就应该是补充而非新建。\n"
    "6. 用户口述的是全新备忘（无时间点、无对应已有笔记）时，用 create_note。\n"
    "7. 若指令包含多个步骤，在 steps 数组中按执行顺序排列。\n"
    "8. 对于在前面步骤中新建的文件夹/文件，后续步骤引用它时 id 留空\"\"，用名称引用。\n"
    "9. needs_confirmation：当你对用户意图把握不准、或指令有歧义、或涉及删除等不可逆操作时设为 true。步骤数量超过 3 个时也设为 true。\n"
    "10. summary：简明概括计划执行的操作，供用户确认用。\n"
    "11. **时间语义匹配**：当用户用「昨天/今天/前天/大前天/上周/本月/X月X号/X月X日」等时间词指代笔记时，必须根据每行后面的「创建时间」判断该项的创建日期是否符合，**不要**用名称去匹配时间词。例如「删掉昨天的笔记」应删除创建时间在昨天的所有文件，而非名称含「昨天」的文件。涉及多条笔记时需设为多步骤（每条一个 delete），且 needs_confirmation=true。\n"
    "12. 每个 action 对象的参数直接平铺在对象中（如 {{\"action\":\"create_note\",\"content\":\"...\"}}），不要嵌套在 parameters 子对象里。\n"
    "13. **新建日程+提醒**：当用户描述一个全新的日程且要求提醒时（如「每天中午12点网课提前3分钟通知」），必须分两步：\n"
    "   步骤1: create_event（title=网课, date=今天或首次发生日期, time=12:00, content=用户原文）\n"
    "   步骤2: set_reminder(name=网课, minutes=3, recurrence=daily/weekly/... , recurrence_end_date=如有结束日期则填)\n"
    "   对于没有具体日期的周期日程（如「每天…」），date 填今天（YYYY-MM-DD）。步骤2 的 target_id 留空，用 name 引用步骤1 创建的名称。\n"
    "   判断标准：目录树中不存在同名日程 + 用户提到了提醒相关词（通知/提醒/和我说/提前），就必须用 create_event + set_reminder 两步！\n"
    "14. 只输出 JSON 对象，不要 markdown 代码块，不要解释。"
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


async def _build_inventory() -> str:
    """构建目录树清单文本（类型 | id | 名称 | 创建时间 | 路径）供 LLM 参考。"""
    tree = await crud.get_folder_tree()
    lines: list[str] = []

    def walk(nodes: list[dict], parent_path: str) -> None:
        for node in nodes:
            name = node["name"]
            path = f"{parent_path}/{name}"
            created = node.get("created_at", "")[:10]  # 只取日期 YYYY-MM-DD
            lines.append(f"folder | {node['id']} | {name} | {created} | {path}")
            for f in node.get("files", []):
                f_created = f.get("created_at", "")[:10]
                lines.append(f"file | {f['id']} | {f['name']} | {f_created} | {path}/{f['name']}")
            walk(node.get("children", []), path)

    walk(tree, "")
    return "\n".join(lines)


async def _build_target_context(file_id: str) -> str:
    """为指定文件构建上下文文本，用于笔记内语音编辑。"""
    doc = await crud.get_file(file_id)
    if doc is None:
        return ""
    content = doc.get("content", "") or ""
    name = doc.get("name", "")
    # 截取内容前 800 字作为参考
    preview = content[:800]
    if len(content) > 800:
        preview += "\n...(内容已截断)"
    return (
        f"## 当前编辑目标\n"
        f"用户正在编辑这篇笔记：\n"
        f"- id: {file_id}\n"
        f"- 名称: {name}\n"
        f"- 内容预览:\n```\n{preview}\n```\n\n"
        f"**重要**：用户的所有修改意图都是针对这篇笔记的。"
        f"请用 append_note(target_id='{file_id}', content='修改内容') 把调整应用到这篇笔记。"
        f"不要创建新笔记！不要找其他目标！\n\n"
    )


async def parse_command(text: str, target_file_id: str | None = None) -> dict:
    """把用户指令文本解析为结构化对象。

    返回：{"steps": [action...], "needs_confirmation": bool, "summary": str}
    会先拉取真实目录树作为上下文，由 LLM 根据语义选出要操作的项的 id。

    若提供 target_file_id，表示用户正在编辑某条笔记，解析时会把该笔记信息注入上下文，
    所有 append_note/edit 操作默认指向该笔记。

    Raises:
        json.JSONDecodeError: 模型输出无法解析为 JSON 时抛出。
    """
    inventory = await _build_inventory()
    now = datetime.now().strftime("%Y-%m-%d（周%u）")

    # 如果有目标文件，注入目标文件上下文
    target_context = ""
    if target_file_id:
        target_context = await _build_target_context(target_file_id)

    system_prompt = _SYSTEM_PROMPT_TEMPLATE.format(
        inventory=inventory or "(空)", now=now, target_context=target_context
    )
    raw = await qwen.chat(system_prompt, text, temperature=0.1)
    cleaned = _strip_code_fence(raw)
    data = json.loads(cleaned)
    # 兼容：LLM 偶尔直接输出 action 数组或单个 action 对象
    if isinstance(data, list):
        data = {"steps": data, "needs_confirmation": False, "summary": ""}
    if isinstance(data, dict) and "steps" not in data and "action" in data:
        # 单个 action 对象
        data = {"steps": [data], "needs_confirmation": False, "summary": ""}
    # 标准化：step 里的 parameters 子对象展平到 step
    data["steps"] = _normalize_steps(data.get("steps", []))
    data.setdefault("needs_confirmation", False)
    data.setdefault("summary", "")

    # 删除操作强制要求二次确认，不依赖 LLM 自觉
    if any(step.get("action") == "delete" for step in data["steps"]):
        data["needs_confirmation"] = True
        if not data["summary"]:
            data["summary"] = "计划执行删除操作"

    return data


def _normalize_steps(steps: list[dict]) -> list[dict]:
    """把步骤中的 parameters 嵌套展平到顶层，并确保 content 字段存在（create_note 时用原始文本兜底）。"""
    result: list[dict] = []
    for step in steps:
        action = step.get("action", "")
        # 如果 LLM 把参数包在 parameters 里，展平
        params = step.get("parameters", {})
        if isinstance(params, dict) and params:
            step = {k: v for k, v in step.items() if k != "parameters"}
            step.update(params)
        # create_note/append_note 的 content 必须是 user_prompt 本身（或 params 里的 content）
        if action == "create_note" and not step.get("content"):
            # 极端情况：content 漏了，用原始文本兜底（但这里拿不到，留 executor 报错）
            pass
        result.append(step)
    return result
