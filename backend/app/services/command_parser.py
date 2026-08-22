"""自然语言 -> 结构化 JSON 指令解析器。

解析时把当前真实目录树喂给 LLM，由 LLM 根据语义直接选出要操作的文件/文件夹 id，
而非依赖字符串模糊匹配。支持多步骤指令与「补充笔记」。
对于涉及日期引用的操作（如「删掉昨天的笔记」），后端预先查询 PostgreSQL 过滤匹配文件，
将结果注入提示词，LLM 只做最终确认，避免幻觉。

输出格式：{"steps": [...], "needs_confirmation": bool, "summary": str}
"""

import json
import re
from datetime import datetime, timedelta

from .. import pg_ops as crud
from . import qwen

# 指令解析系统提示词（运行时拼接目录树清单）
_SYSTEM_PROMPT_TEMPLATE = (
    "你是语音指令解析器。根据用户指令和当前目录树，输出严格的 JSON 对象。\n\n"
    "现在时间是：{now}\n"
    "当前目录树（每行：类型 | id | 名称 | 创建时间 | 完整路径）：\n"
    "{inventory}\n\n"
    "{target_context}"
    "{date_filtered}"
    "{semantic_context}"
    "{date_reference}"
    "支持的 action：\n"
    "- create_note: 新建笔记（无明确时间/日期的备忘）。参数 content(备忘原文), target_folder_id?(可选目录 id；缺省「未分类」), target_folder?(用户提到的目录名，兜底用)。重要：content 只做优化和结构化（修正错别字、整理格式），绝对不要添加用户没说的内容、不要润色扩展、不要添油加醋。\n"
    "- create_event: 新建日程（有明确时间/日期的安排）。参数 title(日程标题), date(日期 YYYY-MM-DD), time(时间 HH:MM，缺省空), content(日程详情), target_folder_id?(可选目录 id), target_folder?(用户提到的目录名，兜底用)。当用户说「安排/预定/约了/XX点XX分/下周一/明天/X月X号」并且涉及具体时间点时用此 action\n"
    "- append_note: 补充/追加内容到已有笔记或日程。参数 target_id(要补充的文件 id), name(用户提到的文件名，兜底用), content(要补充的新内容)。当用户说「补充/加上/添加到XX」时用此 action\n"
    "- set_reminder: 为日程设置提醒。参数 target_id(日程文件 id), name(日程名称，兜底用), minutes(提前多少分钟提醒，0=到点提醒即在日程开始时刻提醒), recurrence(周期：空=一次性, daily=每天, weekly=每周, monthly=每月), recurrence_end_date(周期结束日期 YYYY-MM-DD，如「到10月第一周」需换算为该周周一的日期)。当用户说「提前XX分钟提醒」「每天提醒」「每周X提醒」「到X月X号为止」时用此 action\n"
    "- cancel_reminder: 取消日程的提醒。参数 target_id(日程文件 id), name(日程名称，兜底用)。当用户说「取消提醒」「不要提醒了」时用此 action\n"
    "- update_schedule: 修改已有日程的时间/日期/提醒/重复属性。参数 target_id(日程文件 id), name(日程名称兜底用), date?(YYYY-MM-DD), time?(HH:MM), reminder_minutes?(提前提醒分钟数，0=取消提醒), repeat_enabled?(是否重复 true/false), repeat_unit?(重复单位 seconds/minutes/hours/days), repeat_value?(重复值数字)。当用户在编辑日程时说「改成XX点」「提前XX分钟」「每小时/每X分钟/每天重复」「取消重复」时用此 action；只有修改正文内容时才用 append_note。\n"
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
    "- 「下周X」：参考下方「日期参考」表格中「下周X」对应的日期直接填入，不要自己算！\n"
    "- 「下下周X」：参考下方「日期参考」表格中「下下周X」对应的日期直接填入。\n"
    "- 「上/昨/前」同理反向推算\n"
    "- 「X月X号/X月X日」直接取该日期，年份取当前年份（如果该日期已过，取明年）\n"
    "- 「X分钟后/X小时后/X秒后」= 当前时间 + X（这是倒计时，不是具体钟点）：date=今天，time=换算出的 HH:MM。\n"
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
    "   **倒计时提醒**：若用户说「X分钟后/X小时后提醒我做Y」（相对现在，无具体钟点），则 time=当前时间+X（换算成 HH:MM），set_reminder 的 minutes=0（到点提醒，不是取消！）。例如「3分钟后提醒我出门遛狗」→ create_event(title=遛狗, date=今天, time=当前+3分钟) + set_reminder(name=遛狗, minutes=0)。只有用户明确说「提前X分钟」时才用 minutes=X。\n"
    "14. **主题查询**：当用户说「购物相关的」「关于XX的笔记」等描述性查询时，请查看上面「匹配结果」中的记录——那就是数据库中实际匹配到的笔记/日程。直接操作这些记录，不要说无法筛选或缺少分类系统。如果匹配结果为空，返回空的 steps 即可。\n"
    "15. 只输出 JSON 对象，不要 markdown 代码块，不要解释。"
)


def _fmt_date(value) -> str:
    """安全地将 datetime 或字符串转为 YYYY-MM-DD。"""
    if value is None:
        return ""
    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d")  # type: ignore[union-attr]
    return str(value)[:10]


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
            created = _fmt_date(node.get("created_at"))
            lines.append(f"folder | {node['id']} | {name} | {created} | {path}")
            for f in node.get("files", []):
                f_created = _fmt_date(f.get("created_at"))
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
    ftype = doc.get("type", "note")
    # 截取内容前 800 字作为参考
    preview = content[:800]
    if len(content) > 800:
        preview += "\n...(内容已截断)"

    if ftype == "event":
        action_hint = (
            f"这是一条日程。用户可能要求调整日程的时间/日期/提前提醒/重复周期，"
            f"此时必须用 update_schedule(target_id='{file_id}', ...) 更新日程属性；"
            f"只有用户明确要求修改正文内容时，才用 append_note。"
        )
    else:
        action_hint = (
            f"请用 append_note(target_id='{file_id}', content='调整指令') 把用户意图传递给后续处理。"
        )

    return (
        f"## 当前编辑目标\n"
        f"用户正在编辑这篇{'日程' if ftype == 'event' else '笔记'}：\n"
        f"- id: {file_id}\n"
        f"- 名称: {name}\n"
        f"- 内容预览:\n```\n{preview}\n```\n\n"
        f"**重要**：用户的所有修改意图都是针对这篇{'日程' if ftype == 'event' else '笔记'}的。"
        f"{action_hint}\n"
        f"content 字段填入对笔记的具体操作指令（而非原文照抄），例如：\n"
        f"  - 修改：「把时间改为14:00，日期改为2026-08-12」\n"
        f"  - 删除：「删除日期和时间的行」「去掉第二行」\n"
        f"  - 新增：「补充：记得带毛巾」\n"
        f"不要创建新笔记！不要找其他目标！\n\n"
    )


# 日期关键词 → 相对偏移（天），基于当前日期
_RELATIVE_DATE_PATTERNS = [
    (re.compile(r"今天"), 0),
    (re.compile(r"昨天"), -1),
    (re.compile(r"前天"), -2),
    (re.compile(r"大前天"), -3),
    (re.compile(r"明天"), 1),
    (re.compile(r"后天"), 2),
    (re.compile(r"大后天"), 3),
]

# 绝对日期: "X月X号" / "X月X日"
_ABSOLUTE_DATE_PATTERN = re.compile(r"(\d{1,2})\s*月\s*(\d{1,2})\s*[号日]")


def _extract_date_from_text(text: str, now: datetime) -> str | None:
    """从用户文本中提取日期引用，返回 YYYY-MM-DD 或 None（无日期引用）。

    按优先级：先匹配「今天/昨天/前天」等相对词，再匹配「X月X号」。
    """
    # 1. 相对日期
    for pattern, offset in _RELATIVE_DATE_PATTERNS:
        if pattern.search(text):
            target = now + timedelta(days=offset)
            return target.strftime("%Y-%m-%d")

    # 2. 绝对日期「X月X号/日」
    match = _ABSOLUTE_DATE_PATTERN.search(text)
    if match:
        month = int(match.group(1))
        day = int(match.group(2))
        year = now.year
        # 如果该日期在今年已过，取明年
        candidate = datetime(year, month, day)
        if candidate < now.replace(hour=0, minute=0, second=0, microsecond=0):
            candidate = datetime(year + 1, month, day)
        return candidate.strftime("%Y-%m-%d")

    return None


async def _build_date_filtered_context(text: str) -> str:
    """如果用户文本中包含日期引用，查询 PostgreSQL 过滤匹配文件，返回预过滤上下文。

    返回空字符串表示没有日期引用或无匹配文件。
    """
    now = datetime.now()
    date_str = _extract_date_from_text(text, now)
    if not date_str:
        return ""

    files = await crud.find_files_by_created_date(date_str)
    if not files:
        return (
            f"## 日期过滤结果\n"
            f"用户提到的日期为 {date_str}，但数据库中**没有**该日期创建的笔记或日程。\n"
            f"请如实告知用户没有匹配项，不要虚构任何文件。\n\n"
        )

    lines = [f"## 日期过滤结果：{date_str} 创建的笔记/日程"]
    for f in files:
        name = f.get("name", "")
        fid = f.get("id", "")
        ftype = f.get("type", "note")
        type_label = "日程" if ftype == "event" else "笔记"
        lines.append(f"{type_label} | {fid} | {name}")
    lines.append(f"\n以上是数据库中 {date_str} 创建的 {len(files)} 条记录。")
    lines.append("如果用户要求删除/操作这些笔记，请只操作上面的记录，不要虚构不存在的文件。\n")
    return "\n".join(lines)


async def _build_semantic_context(text: str) -> str:
    """语义搜索 + 关键词搜索：先用用户文本中的名词做关键词匹配，再用 embedding。

    解决「番茄/西红柿」「好吃的/美食记录」等异名同意的问题。
    返回空字符串表示没有匹配结果。
    """
    # 1. 提取用户文本中的关键词，做字面正则搜索（可靠性更高）
    #    取 2-4 字长度的中文词作为关键词
    keywords = set(re.findall(r"[\u4e00-\u9fa5]{2,4}", text))
    # 去掉常见的功能词
    stop_words = {"帮我", "找到", "并且", "删掉", "一下", "那个", "这个", "那些", "这些", "删除", "笔记", "日程"}
    keywords -= stop_words

    keyword_files: list[dict] = []
    seen_ids: set[str] = set()
    if keywords:
        for kw in keywords:
            results = await crud.find_files_by_filter({"name": {"$regex": kw, "$options": "i"}}, limit=3)
            for f in results:
                fid = f.get("id", "")
                if fid not in seen_ids:
                    seen_ids.add(fid)
                    keyword_files.append(f)

    # 2. 语义搜索（embedding）：召回名称不同但语义相关的文件
    semantic_files = await crud.search_files_semantic(text, top_k=10, threshold=0.55)

    # 3. 合并：关键词匹配优先排在前面（更可靠），语义匹配作为补充
    semantic_seen = set(seen_ids)
    combined: list[dict] = list(keyword_files)
    for f in semantic_files:
        fid = f.get("id", "")
        if fid not in seen_ids:
            seen_ids.add(fid)
            combined.append(f)

    if not combined:
        return ""

    keyword_ids = {kf.get("id") for kf in keyword_files}

    lines = ["## 匹配结果"]
    # 关键词匹配组
    kw_items = [f for f in combined if f.get("id") in keyword_ids]
    if kw_items:
        lines.append("（关键词匹配，字面包含相同文字，可靠性高）")
        for f in kw_items:
            ftype = f.get("type", "note")
            type_label = "日程" if ftype == "event" else "笔记"
            lines.append(f"{type_label} | {f.get('id')} | {f.get('name')}")

    # 语义匹配组（排除已在关键词组中的）
    sem_items = [f for f in combined if f.get("id") not in keyword_ids]
    if sem_items:
        lines.append("（语义匹配，名称不同但含义相关，仅供参考）")
        for f in sem_items:
            ftype = f.get("type", "note")
            type_label = "日程" if ftype == "event" else "笔记"
            lines.append(f"{type_label} | {f.get('id')} | {f.get('name')}")

    lines.append(f"\n以上共 {len(combined)} 条可能匹配的记录。")
    lines.append("**重要**：上面的匹配结果就是根据用户描述从数据库中实际查到的笔记/日程。")
    lines.append("如果用户说「购物相关的」「关于XX的」等描述性查询，请直接把匹配到的记录作为结果。")
    lines.append("不要认为需要额外的「主题标记」或「分类系统」——关键词匹配本身就是按内容筛选。\n")
    return "\n".join(lines)


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
    now = datetime.now().strftime("%Y-%m-%d %H:%M（周%u）")

    # 如果有目标文件，注入目标文件上下文
    target_context = ""
    if target_file_id:
        target_context = await _build_target_context(target_file_id)

    # 如果有日期引用，预查询过滤匹配文件
    date_filtered = await _build_date_filtered_context(text)

    # 语义搜索：用用户原文做 embedding 召回语义相关文件
    semantic_context = await _build_semantic_context(text)

    system_prompt = _SYSTEM_PROMPT_TEMPLATE.format(
        inventory=inventory or "(空)", now=now, target_context=target_context,
        date_filtered=date_filtered, semantic_context=semantic_context,
        date_reference=_build_date_reference(),
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

    # 删除操作强制要求二次确认（在聊天中完成确认流程）
    if any(step.get("action") == "delete" for step in data["steps"]):
        data["needs_confirmation"] = True
        if not data["summary"]:
            data["summary"] = "计划执行删除操作"

    return data


async def build_agent_context(text: str, target_file_id: str | None = None) -> str:
    """构建 TRAE agent 上下文：目录树 + 日期过滤 + 语义搜索 + 目标文件。

    供 chat_stream 的 agent 循环使用，让 LLM 在迭代决策中始终看到最新的上下文。
    """
    inventory = await _build_inventory()
    now = datetime.now().strftime("%Y-%m-%d %H:%M（周%u）")
    date_ref = _build_date_reference()

    target_context = ""
    if target_file_id:
        target_context = await _build_target_context(target_file_id)

    date_filtered = await _build_date_filtered_context(text)
    semantic_context = await _build_semantic_context(text)

    parts: list[str] = [f"当前时间：{now}", date_ref]
    if inventory:
        parts.append(f"## 目录树\n（格式：类型 | id | 名称 | 创建日期 | 路径）\n{inventory}")
    if date_filtered:
        parts.append(date_filtered)
    if semantic_context:
        parts.append(semantic_context)
    if target_context:
        parts.append(target_context)
    return "\n\n".join(parts)


def _build_date_reference() -> str:
    """构建未来日期对照表，供 LLM 直接查表换算「下周X」「下下周X」等表达。"""
    today = datetime.now().date()
    weekday_names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    today_name = weekday_names[today.weekday()]

    # 找到下周一
    days_until_monday = (7 - today.weekday()) % 7 or 7
    next_monday = today + timedelta(days=days_until_monday)
    # 下下周一
    next_next_monday = next_monday + timedelta(days=7)

    lines = [f"（今天是 {today.strftime('%Y-%m-%d')} {today_name}）", ""]
    lines.append("下周：")
    for i, name in enumerate(weekday_names):
        date = next_monday + timedelta(days=i)
        lines.append(f"  下周{name}: {date.strftime('%Y-%m-%d')}")
    lines.append("")
    lines.append("下下周：")
    for i, name in enumerate(weekday_names):
        date = next_next_monday + timedelta(days=i)
        lines.append(f"  下下周{name}: {date.strftime('%Y-%m-%d')}")

    return "## 日期参考\n" + "\n".join(lines)


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
