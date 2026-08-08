"""AI 指令路由：自然语言 -> 结构化 JSON -> 执行。

支持多步骤指令与确认流程。还提供流式多轮聊天接口。
"""

import json
import uuid
from datetime import datetime

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from .. import crud
from ..schemas import ChatRequest, CommandRequest, CommandResult, ConfirmRequest
from ..services import command_executor, command_parser, geo, qwen

router = APIRouter(prefix="/api/ai", tags=["ai"])

# 待确认指令的内存暂存：confirmation_id -> steps
_pending: dict[str, list[dict]] = {}

# 多轮对话上下文：conversation_id -> [(role, content), ...]
# 最多保留 20 轮（40 条消息）
_conversations: dict[str, list[dict]] = {}
_MAX_HISTORY = 40

# 触发确认的步骤数阈值
_CONFIRM_STEP_THRESHOLD = 3

# 聊天系统提示词
_CHAT_SYSTEM_PROMPT = (
    "你是 SayMark 语音记事本助手。帮助用户管理笔记、日程、文件夹。\n"
    "现在是：{current_time}\n"
    "注意：当对话历史中出现「[已执行] xxx」的系统消息时，表示该操作已经真实完成（笔记已写入、日程已创建、文件已删除等），"
    "你需要根据这个结果自然地回复用户，而不是说「我可以帮你」或再次尝试执行。\n"
    "当出现「[执行失败] xxx」时，如实告知用户操作未成功及原因。\n"
    "当出现「[需确认] xxx」时，表示该操作需要用户二次确认（如删除等不可逆操作），"
    "请告知用户该操作需要在主界面指令模式中确认后才能执行，不要在聊天中假装已执行。\n"
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
    except Exception as e:
        return CommandResult(
            action="unknown",
            success=False,
            message=f"指令解析失败：{e}",
        )

    steps = parsed.get("steps", [])
    needs_confirm = bool(parsed.get("needs_confirmation")) or len(steps) > _CONFIRM_STEP_THRESHOLD

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

    command_executor.set_device_id(body.device_id or "")
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
    result = await command_executor.execute_steps(steps)
    return result


def _format_result_detail(result: dict) -> str:
    """从执行结果中提取关键信息，供 AI 对话上下文使用。"""
    data = result.get("data")
    if not isinstance(data, dict):
        return ""
    parts: list[str] = []
    name = data.get("name", "")
    item_id = data.get("id", "")
    if name:
        parts.append(f"「{name}」")
    if item_id:
        parts.append(f"id={item_id}")
    date = data.get("date", "")
    if date:
        parts.append(f"日期={date}")
    time = data.get("time", "")
    if time:
        parts.append(f"时间={time}")
    return "（" + "，".join(parts) + "）" if parts else ""


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


# ----------------------------- 流式多轮聊天 -----------------------------


@router.post("/chat/stream")
async def chat_stream(body: ChatRequest):
    """流式多轮聊天（SSE）+ 自动执行用户指令 + 地理位置上下文。

    Body: {"text": "用户消息", "conversation_id": "可选", "latitude": 31.2, "longitude": 121.4}
    首行返回 {"conversation_id": "xxx"}，随后逐 token SSE 流式推送。
    如果用户消息包含可执行指令，先真实执行，再把结果注入对话上下文。
    如果有坐标，自动注入位置信息供 AI 参考。
    """
    text = body.text.strip()
    conv_id = body.conversation_id.strip()
    user_lat = body.latitude
    user_lon = body.longitude
    device_id = body.device_id.strip()

    if not text:
        async def empty_gen():
            yield "data: 请说点什么吧\n\ndata: [DONE]\n\n"
        return StreamingResponse(empty_gen(), media_type="text/event-stream")

    if not conv_id:
        conv_id = uuid.uuid4().hex

    if conv_id not in _conversations:
        _conversations[conv_id] = [{"role": "system", "content": _CHAT_SYSTEM_PROMPT.format(current_time=datetime.now().strftime("%Y年%m月%d日 %H:%M"))}]

    history = _conversations[conv_id]

    # 尝试将用户消息解析为指令并真实执行
    # 如果用户用了模糊指代（"这些/那条/刚才的"），把上一轮 AI 回复作为上下文
    parser_text = text
    if _has_vague_reference(text):
        last_assistant = _last_assistant_content(history)
        if last_assistant:
            parser_text = f"[上轮AI回复] {last_assistant}\n\n[用户指令] {text}"

    execution_note: str | None = None
    try:
        parsed = await command_parser.parse_command(parser_text)
        steps = parsed.get("steps", [])
        needs_confirm = bool(parsed.get("needs_confirmation")) or len(steps) > _CONFIRM_STEP_THRESHOLD
        if steps and not needs_confirm:
            if body.target_file_id is None:
                command_executor.set_device_id(body.device_id)
            result = await command_executor.execute_steps(steps)
            msg = result.get("message", "")
            if result.get("success"):
                detail = _format_result_detail(result)
                execution_note = f"[已执行] {msg}{detail}"
            else:
                execution_note = f"[执行失败] {msg}"
        elif steps and needs_confirm:
            # 有步骤但需要确认（如删除操作），注入提示让 AI 告知用户
            summary = parsed.get("summary", "")
            execution_note = f"[需确认] {summary}，请在主界面指令模式中确认后执行"
    except Exception:
        pass  # 非指令文本，走正常聊天

    # 注入执行结果到对话上下文
    # 位置上下文：同步位置到 Profile + 注入已知地点
    location_note: str | None = None
    if user_lat is not None and user_lon is not None:
        if device_id:
            # 异步同步位置到用户 Profile
            await crud.update_user_location(device_id, user_lat, user_lon)
            # 获取用户所有已知地点
            places = await crud.get_user_places(device_id)
        else:
            places = []

        address = await geo.reverse_geocode(user_lat, user_lon)
        parts = []
        if address:
            short = address.split(",")[0] if "," in address else address[:30]
            parts.append(f"用户当前在：{short}（{user_lat:.4f}, {user_lon:.4f}）")
        else:
            parts.append(f"用户当前坐标：({user_lat:.4f}, {user_lon:.4f})")

        if places:
            place_lines = "\n".join(
                f"  - {p['name']}（{p['lat']:.4f}, {p['lon']:.4f}）" for p in places
            )
            parts.append(f"用户保存的常用地点（优先使用，不需要再查 Nominatim）：\n{place_lines}")

        parts.append("回答涉及地点/距离/出行时请基于以上坐标信息，不要编造。用户提到的地名优先从常用地点中匹配。")
        location_note = "[位置] " + " ".join(parts)
    if location_note:
        history.append({"role": "system", "content": location_note})

    history.append({"role": "user", "content": text})
    if execution_note:
        history.append({"role": "system", "content": execution_note})

    if len(history) > _MAX_HISTORY + 2:
        _conversations[conv_id] = [history[0]] + history[-(_MAX_HISTORY):]
        history = _conversations[conv_id]

    messages = list(history)

    async def event_stream():
        yield f"data: {json.dumps({'conversation_id': conv_id})}\n\n"
        # 如果有执行结果，作为「思考过程」先发给前端
        if execution_note:
            if execution_note.startswith("[需确认]"):
                thinking_text = execution_note.removeprefix("[需确认] ")
                yield f"data: {json.dumps({'thinking': f'⚠️ 需要确认：{thinking_text}'})}\n\n"
            else:
                thinking_text = execution_note.removeprefix("[已执行] ").removeprefix("[执行失败] ")
                prefix = "✅ 已执行" if execution_note.startswith("[已执行]") else "❌ 执行失败"
                yield f"data: {json.dumps({'thinking': f'{prefix}：{thinking_text}'})}\n\n"
        try:
            full_response = ""
            async for token in qwen.chat_stream(messages, temperature=0.7):
                full_response += token
                yield f"data: {json.dumps(token)}\n\n"
            history.append({"role": "assistant", "content": full_response})
            if len(history) > _MAX_HISTORY + 2:
                _conversations[conv_id] = [history[0]] + history[-(_MAX_HISTORY):]
        except Exception as e:
            yield f"data: {json.dumps(f'[错误] {str(e)}')}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
