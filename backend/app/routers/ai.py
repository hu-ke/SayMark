"""AI 指令路由：自然语言 -> 结构化 JSON -> 执行。

支持多步骤指令与确认流程。还提供流式多轮聊天接口。
"""

import json
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from loguru import logger

from .. import pg_ops as crud
from ..schemas import ChatRequest, CommandRequest, CommandResult, ConfirmRequest
from ..services import command_executor, command_parser, geo, qwen

router = APIRouter(prefix="/api/ai", tags=["ai"])

# 加载 SQL Schema 文档
_SCHEMA_DOC_PATH = Path(__file__).resolve().parent.parent.parent / "sql_schema.md"
_SCHEMA_DOC = _SCHEMA_DOC_PATH.read_text(encoding="utf-8") if _SCHEMA_DOC_PATH.exists() else ""

# 待确认指令的内存暂存：confirmation_id -> steps
_pending: dict[str, list[dict]] = {}

# 多轮对话上下文：conversation_id -> [(role, content), ...]
# 最多保留 20 轮（40 条消息）
_conversations: dict[str, list[dict]] = {}
_MAX_HISTORY = 40

# 聊天内待确认的操作步骤：conversation_id -> steps
_pending_chat_steps: dict[str, list[dict]] = {}

_CONFIRM_WORDS = {"确认", "确认删除", "是的", "可以", "行", "ok", "yes", "确定", "删吧", "执行", "好", "好的"}
_CANCEL_WORDS = {"取消", "不要", "算了", "不了", "no", "不删了", "不删"}
_SKIP_CONFIRM_WORDS = {"不用确认", "直接删", "别确认", "不需要确认", "不用二次确认", "别问了", "直接执行"}


def _is_confirm(text: str) -> bool:
    """检查用户文本是否为确认回复（短文本 + 含确认关键词）。"""
    t = text.strip().lower()
    if len(t) > 10:
        return False
    return any(kw in t for kw in _CONFIRM_WORDS)


def _is_cancel(text: str) -> bool:
    """检查用户文本是否为取消回复。"""
    t = text.strip().lower()
    if len(t) > 10:
        return False
    return any(kw in t for kw in _CANCEL_WORDS)


def _is_skip_confirm(text: str) -> bool:
    """用户明确要求跳过二次确认时返回 True。"""
    t = text.strip().lower()
    return any(w in t for w in _SKIP_CONFIRM_WORDS)


# 聊天系统提示词
_CHAT_SYSTEM_PROMPT = (
    "你是 SayMark 语音记事本助手。帮助用户管理笔记、安排、闹钟、文件夹。\n"
    "现在是：{current_time}\n"
    "注意：当对话历史中出现「[已执行] xxx」的系统消息时，表示该操作已经真实完成（笔记已写入、日程已创建、文件已删除等），"
    "你需要根据这个结果自然地回复用户，而不是说「我可以帮你」或再次尝试执行。\n"
    "当出现「[执行失败] xxx」时，如实告知用户操作未成功及原因。\n"
    "当出现「[待确认] xxx」时，表示用户请求了需要二次确认的操作。"
    "你只需要告诉用户将要执行的操作内容，并询问「确认吗？请回复确认或取消」。"
    "**绝对不要**自己编造或描述被操作笔记的具体内容，因为你不知道笔记里写了什么。\n"
    "当出现「[位置] 用户当前在：xxx（坐标）」时，你已知用户的真实位置。关于地点、距离、通勤的问题，"
    "请基于此坐标判断，使用 Haversine 公式估算直线距离（地球半径6371km），不要凭空编造距离和时间。"
    "如果没有位置信息，不要假装知道用户在哪。\n"
    "回复风格：简洁、友好，用中文。如果没有可执行的操作，正常聊天回答问题即可。"
)


@router.post("/command", response_model=CommandResult)
async def command(body: CommandRequest):
    """解析自然语言指令为 JSON 并执行，返回统一结果对象。"""
    try:
        parsed = await command_parser.parse_command(body.text, target_file_id=body.target_file_id)
        logger.info(f"解析指令：{parsed}")
    except Exception as e:
        return CommandResult(
            action="unknown",
            success=False,
            message=f"指令解析失败：{e}",
        )

    steps = parsed.get("steps", [])
    needs_confirm = bool(parsed.get("needs_confirmation")) or len(steps) > 3

    if needs_confirm and steps:
        confirmation_id = uuid.uuid4().hex
        _pending[confirmation_id] = steps
        summary = parsed.get("summary") or f"计划执行 {len(steps)} 个操作"
        return CommandResult(
            action="confirm_required",
            success=False,
            message=summary,
            data={"confirmation_id": confirmation_id, "steps": steps},
        )

    command_executor.set_device_id("")
    result = await command_executor.execute_steps(steps)
    return result


@router.post("/command/confirm", response_model=CommandResult)
async def confirm_command(body: ConfirmRequest):
    """用户确认/取消后执行或丢弃暂存的指令。"""
    steps = _pending.pop(body.confirmation_id, None)
    if steps is None:
        return CommandResult(
            action="confirm_required",
            success=False,
            message="确认已过期或不存在，请重新输入指令",
        )
    if not body.confirmed:
        return CommandResult(
            action="cancelled",
            success=True,
            message="已取消执行",
        )
    command_executor.set_device_id("")
    result = await command_executor.execute_steps(steps)
    return result


_VAGUE_WORDS = {"这些", "那个", "那些", "这条", "那条", "刚才的", "上面的", "前面说的", "把上面", "加进去", "加到我", "帮我加", "加到日程", "加到笔记"}


def _has_vague_reference(text: str) -> bool:
    """检测用户消息是否包含模糊指代（需要上一轮 AI 回复做上下文）。"""
    return any(w in text for w in _VAGUE_WORDS)


def _last_assistant_content(history: list[dict]) -> str | None:
    """取最近一条 assistant 消息的内容（截取前 500 字）。"""
    for msg in reversed(history):
        if msg.get("role") == "assistant":
            content = msg.get("content", "")
            return content[:500] if content else None
    return None


# ----------------------------- TRAE Agent 核心 -----------------------------

# Agent 系统提示词：告诉 LLM 它的角色、可用工具、输出格式
_AGENT_SYSTEM_PROMPT = f"""\
你是 SayMark 语音记事本助手。你通过调用工具来管理用户的笔记、日程和文件夹。

## 数据库 Schema

{_SCHEMA_DOC}

## 可用工具

调用格式：{{"tool_calls": [{{"action": "<工具名>", "params": {{<参数>}}}}]}}

1. run_query — 执行 SQL SELECT 查询检索数据（只读）
   参数：sql(完整的 SELECT 查询语句)
   注意：只能用于查询（SELECT），写操作请用下面的专用工具。查询结果会以 JSON 数组返回。

2. create_note — 创建笔记（无明确时间的备忘）
   参数：content(备忘原文), target_folder_id?(目录id)
   重要：content 只做优化和结构化（修正错别字、整理格式），**绝对不要**添加用户没说的内容、不要润色扩展、不要添油加醋。

3. create_appointment — 创建安排（有明确时间的一次性事项，倒计时「X分钟后/X小时后」也算）
   参数：title(标题), date(YYYY-MM-DD), time?(HH:MM), content(详情)
   注意：「X分钟后/小时后」→ date=今天, time=当前时间+X；不要用 create_alarm。

4. append_note — 补充内容到已有笔记、安排或闹钟
   参数：target_id?(文件id), name?(文件名兜底), content(要补充的内容)

5. create_alarm — 创建闹钟（周期性提醒，如「每天1点喊我睡觉」）
   参数：name(名称), time(HH:MM 触发时间), recurrence(daily/weekly/monthly，缺省 daily), content(备注)
   注意：只有「每天/每周/每月 + 时间」的周期性提醒才用 create_alarm；一次性倒计时用 create_appointment。

6. create_folder — 创建文件夹
   参数：name, parent_folder_id?(父目录id)

7. rename — 重命名文件或文件夹
   参数：type("file"|"folder"), target_id?(id), name?(原名兜底), new_name

8. delete — 删除文件或文件夹（需二次确认！）
   参数：type("file"|"folder"), target_id?(id), name?(名称兜底)

9. move_file — 移动文件
   参数：file_id?(id), file_name?(文件名兜底), to_folder_id?(目标目录id), to_folder?(目标目录名兜底)

10. list — 列出目录内容
    参数：target_folder_id?(目录id), path?(目录名兜底)

11. locate_folder — 定位文件夹
    参数：target_id?(id), name?(名称兜底)

12. save_place — 保存地点
    参数：name(地名), lat(纬度), lon(经度)

13. update_appointment — 修改已有安排的日期/时间/标题
    参数：target_id?(安排id), name?(名称兜底), date?(YYYY-MM-DD), time?(HH:MM), content?(正文)

14. update_alarm — 修改已有闹钟的时间/周期
    参数：target_id?(闹钟id), name?(名称兜底), time?(HH:MM), recurrence?(daily/weekly/monthly), content?(备注)

15. delete_alarm — 删除闹钟
    参数：target_id?(闹钟id), name?(名称兜底)

## 输出格式

- 需要调用工具时（可一次多个），必须包含 thinking 字段说明你的计划：
  {{"thinking": "简短解释你打算做什么以及为什么", "tool_calls": [{{"action": "run_query", "params": {{"sql": "SELECT ..."}}}}, ...]}}

- 任务完成只需回复用户时，也必须包含 thinking 字段总结：
  {{"thinking": "简短总结完成了什么", "done": true, "reply": "对用户说的完整回复"}}

## 核心规则

1. **优先用 run_query 查询信息**：需要查找已有笔记/安排/闹钟/文件夹时，先生成 SQL 查询。
2. 区分笔记 / 安排 / 闹钟：有具体未来时间点（一次性）→ create_appointment；「X分钟后/X小时后」的倒计时也是一次性 → create_appointment(date=今天, time=当前+X)；周期性提醒（每天/每周/每月 + 时间）→ create_alarm；只是记东西 → create_note。
3. 操作已存在的项时，先 run_query 找到 id，再操作。
4. 删除操作需用户确认：输出 done 并在 reply 中询问。
5. **创建安排/闹钟一步到位**：安排和闹钟是独立实体，各用一条工具调用创建即可，不要分两步。例如「每天中午12点喊我午休」→ create_alarm(name=午休, time=12:00, recurrence=daily)。
6. **创建笔记时禁止添油加醋**：用户说「记一下：今天买了苹果」→ content="今天买了苹果"（只修正错别字和格式），**不要**扩展成「今天买了苹果，苹果富含维生素…」之类的废话。你只是帮用户整理，不是代用户写作。
7. 只输出 JSON，不要 markdown 代码块。"""

_MAX_AGENT_ITERATIONS = 5  # agent 循环最大迭代次数


def _sse(data: dict) -> str:
    """生成 SSE 事件字符串。"""
    return f"data: {json.dumps(data)}\n\n"


def _think_start(title: str = "正在处理...") -> str:
    """开始一段思考过程（客户端展示可折叠卡片）。"""
    return _sse({"thinking_start": title})


def _think_step(text: str) -> str:
    """思考过程中的一个步骤。"""
    return _sse({"thinking_step": text})


def _think_end() -> str:
    """思考过程结束（客户端收起卡片）。"""
    return _sse({"thinking_end": None})


def _think_text(text: str) -> str:
    """思考卡片内的实时文本（打字机效果）。"""
    return _sse({"thinking_text": text})


def _action_label(step: dict) -> str:
    """生成步骤的可读描述（用于 thinking 展示）。"""
    action = step.get("action", "")
    name = step.get("name", "") or step.get("title", "") or step.get("target", "") or ""
    name_part = f"「{name}」" if name else ""
    labels: dict[str, str] = {
        "create_note": f"创建笔记{name_part}",
        "create_appointment": f"创建安排{name_part}",
        "create_alarm": f"创建闹钟{name_part}",
        "append_note": f"补充内容到{name_part or '笔记'}",
        "update_appointment": f"调整安排{name_part}",
        "update_alarm": f"调整闹钟{name_part}",
        "delete_alarm": f"删除闹钟{name_part}",
        "save_place": f"保存地点{name_part}",
        "create_folder": f"创建文件夹{name_part}",
        "rename": f"重命名{name_part}",
        "delete": f"删除{name_part}",
        "move_file": f"移动{name_part or '文件'}",
        "locate_folder": f"定位文件夹{name_part}",
        "list": f"列出{name_part or '内容'}",
    }
    return labels.get(action, f"执行{action}")


def _parse_agent_response(raw: str) -> dict:
    """解析 agent 的 JSON 响应。

    Returns:
        {"tool_calls": [...]} 或 {"done": True, "reply": "..."} 或 {}（解析失败）。
    """
    import re as _re
    cleaned = raw.strip()
    # 去 markdown 代码块
    fence = _re.compile(r"^```(?:json)?\s*(.*?)\s*```$", _re.DOTALL | _re.IGNORECASE)
    m = fence.match(cleaned)
    if m:
        cleaned = m.group(1).strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.lstrip("`").strip()
    if cleaned.endswith("```"):
        cleaned = cleaned.rstrip("`").strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return {}


def _tool_call_to_step(tc: dict) -> dict:
    """将 agent 的 tool_call 转为 executor 能识别的扁平 step dict。"""
    params = tc.get("params", {}) or {}
    step = {"action": tc.get("action", "")}
    step.update(params)
    return step


def _format_observation(results: list[dict]) -> str:
    """将工具执行结果格式化为 agent 可读的观察消息。"""
    lines: list[str] = []
    for r in results:
        status = "成功" if r.get("success") else "失败"
        msg = r.get("message", "")
        lines.append(f"- [{status}] {msg}")
    return "工具执行结果：\n" + "\n".join(lines)


def _trim_history(history: list[dict], conv_id: str) -> None:
    """裁剪过长的对话历史。"""
    if len(history) > _MAX_HISTORY + 2:
        _conversations[conv_id] = [history[0]] + history[-(_MAX_HISTORY):]


async def _build_location_note(lat: float | None, lon: float | None, device_id: str) -> str | None:
    """构建位置上下文系统消息。"""
    if lat is None or lon is None:
        return None
    if device_id:
        await crud.update_user_location(device_id, lat, lon)
        places = await crud.get_user_places(device_id)
    else:
        places = []
    address = await geo.reverse_geocode(lat, lon)
    parts: list[str] = []
    if address:
        short = address.split(",")[0] if "," in address else address[:30]
        parts.append(f"用户当前在：{short}（{lat:.4f}, {lon:.4f}）")
    else:
        parts.append(f"用户当前坐标：({lat:.4f}, {lon:.4f})")
    if places:
        place_lines = "\n".join(f"  - {p['name']}（{p['lat']:.4f}, {p['lon']:.4f}）" for p in places)
        parts.append(f"用户保存的常用地点（优先使用，不需要再查 Nominatim）：\n{place_lines}")
    parts.append("回答涉及地点/距离/出行时请基于以上坐标信息，不要编造。用户提到的地名优先从常用地点中匹配。")
    return "[位置] " + " ".join(parts)


# ----------------------------- 流式多轮聊天 -----------------------------


@router.post("/chat/stream")
async def chat_stream(body: ChatRequest):
    """流式多轮聊天（SSE）+ TRAE Agent 循环。

    流程：Task Init → Agent Think → Tool Call → Execute → Observe → 循环 → Done。
    """

    async def event_stream():
        text = body.text.strip()
        user_lat = body.latitude
        user_lon = body.longitude
        device_id = body.device_id.strip()
        conv_id = body.conversation_id.strip() or uuid.uuid4().hex

        # 1. Task Init: 立即返回 conversation_id
        yield f"data: {json.dumps({'conversation_id': conv_id, 'status': 'loading'})}\n\n"
        if not text:
            yield "data: 请说点什么吧\n\ndata: [DONE]\n\n"
            return

        thinking_active = False  # 跟踪是否启动了思考卡片

        def _step(text: str):
            """发出一个思考步骤。首次自动打开思考卡片。"""
            nonlocal thinking_active
            if not thinking_active:
                thinking_active = True
                return _think_start() + _think_step(text)
            return _think_step(text)

        # 2. 构建 agent 上下文（目录树 + 日期过滤 + 语义搜索）
        yield _step("🔍 正在检索相关文件和笔记...")
        agent_context = await command_parser.build_agent_context(text)
        location_note = await _build_location_note(user_lat, user_lon, device_id)

        # 3. 处理待确认操作（用户回复「确认」或「取消」）
        pending_steps = _pending_chat_steps.pop(conv_id, None)
        if pending_steps is not None:
            if _is_confirm(text):
                created: dict[str, str] = {}
                for step in pending_steps:
                    label = _action_label(step)
                    command_executor.set_device_id(device_id)
                    r = await command_executor.execute(step)
                    if r.get("success"):
                        if step.get("action") == "create_folder":
                            d = r.get("data") or {}
                            if d.get("id") and d.get("name"):
                                created[d["name"]] = d["id"]
                        yield _step(f"{label} → {r.get('message', '完成')}")
                    else:
                        yield _step(f"{label} → {r.get('message', '失败')}")
                        break

                obs = _format_observation([{"success": True, "message": "已执行用户确认的待处理操作"}])
                text = f"[系统通知] 用户确认了之前的待处理操作，已执行完成。{chr(10)}{obs}{chr(10)}现在请根据操作结果回复用户。"

            elif _is_cancel(text):
                yield _step("已取消")
                text = "[系统通知] 用户取消了之前的待处理操作。请告知用户已取消。"
            else:
                _pending_chat_steps[conv_id] = pending_steps

        # 4. 初始化 agent 消息
        system_msg = _AGENT_SYSTEM_PROMPT + "\n\n" + agent_context
        if location_note:
            system_msg += "\n\n" + location_note

        messages: list[dict] = [{"role": "system", "content": system_msg}]

        # 注入最近几轮对话历史（最多 6 条 user/assistant 消息），帮助处理模糊指代
        recent_history = [h for h in _conversations.get(conv_id, [])
                          if h.get("role") in ("user", "assistant")][-6:]
        messages.extend(recent_history)

        messages.append({"role": "user", "content": text})

        # 5. Agent 循环：Think → Act → Observe
        yield _step("AI 正在分析请求...")
        final_reply: str | None = None

        for iteration in range(_MAX_AGENT_ITERATIONS):
            try:
                raw_response = await qwen.chat_messages(messages, temperature=0.1)
            except Exception as e:
                logger.error(f"Agent LLM 调用失败: {e}")
                final_reply = f"抱歉，处理请求时出错了：{e}"
                break

            agent_output = _parse_agent_response(raw_response)

            # 提取并流式展示 AI 的思考过程（打字机效果）
            ai_thought = agent_output.get("thinking", "")
            if ai_thought:
                accumulated = ""
                import asyncio
                for char in ai_thought:
                    accumulated += char
                    yield _think_text(accumulated)
                    await asyncio.sleep(0.015)  # 打字机效果

            # 路径 A：有 tool_calls → 执行工具，反馈观察
            tool_calls = agent_output.get("tool_calls", [])
            if tool_calls:
                # 删除操作强制二次确认（除非用户明确说跳过）
                has_delete = any(tc.get("action") == "delete" for tc in tool_calls)
                if has_delete and not _is_skip_confirm(body.text.strip()):
                    pending = [_tool_call_to_step(tc) for tc in tool_calls]
                    _pending_chat_steps[conv_id] = pending
                    labels = [_action_label(s) for s in pending]
                    final_reply = f"即将执行：{'；'.join(labels)}\n\n请回复「确认」执行，或「取消」放弃。"
                    break

                results: list[dict] = []
                for tc in tool_calls:
                    step = _tool_call_to_step(tc)
                    label = _action_label(step)

                    command_executor.set_device_id(device_id)
                    result = await command_executor.execute(step)
                    results.append(result)

                    msg = result.get("message", "完成")
                    yield _step(f"{label} → {msg}")


                # 将观察注入消息，继续循环
                observation = _format_observation(results)
                messages.append({"role": "assistant", "content": raw_response})
                messages.append({"role": "user", "content": f"[观察] {observation}\n\n请根据以上执行结果决定下一步：继续调用工具，还是回复用户。"})
                continue

            # 路径 B：done → 获取最终回复
            if agent_output.get("done"):
                final_reply = agent_output.get("reply", "")
                break

            # 路径 C：无法解析 → 将原始文本作为最终回复
            if raw_response.strip():
                final_reply = raw_response.strip()
            else:
                final_reply = "好的，已完成。"
            break

        # 6. 没有最终回复时的兜底
        if final_reply is None:
            final_reply = "好的，已完成操作。"

        # 7. 结束思考卡片，流式输出最终回复 + 保存历史
        if thinking_active:
            yield _think_end()
        history = _conversations.setdefault(conv_id, [])
        history.append({"role": "user", "content": body.text.strip()})

        try:
            for chunk in _split_for_streaming(final_reply):
                yield f"data: {json.dumps(chunk)}\n\n"
            history.append({"role": "assistant", "content": final_reply})
        except Exception as e:
            yield f"data: {json.dumps(f'[错误] {str(e)}')}\n\n"
        finally:
            _trim_history(history, conv_id)
            yield "data: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


def _split_for_streaming(text: str, chunk_size: int = 4) -> list[str]:
    """将最终回复按字符拆分为小块，模拟流式输出。"""
    import re as _re
    # 按中文标点 + 换行切分，保持自然停顿
    parts = _re.split(r"(?<=[。！？\n，])", text)
    chunks: list[str] = []
    buf = ""
    for p in parts:
        buf += p
        if len(buf) >= chunk_size:
            chunks.append(buf)
            buf = ""
    if buf:
        chunks.append(buf)
    return chunks or [text]
