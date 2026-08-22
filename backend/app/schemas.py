"""pydantic 请求/响应模型。

约定：ID 字段用字符串；日期用 ISO 字符串。
"""

from typing import Any, List, Optional

from pydantic import BaseModel, ConfigDict


# ----------------------------- 请求模型 -----------------------------


class FolderCreate(BaseModel):
    name: str
    parent_id: Optional[str] = None  # 缺省为顶级目录


class FolderUpdate(BaseModel):
    name: str


class FileCreate(BaseModel):
    name: str
    content: str
    parent_id: str
    type: str = "note"  # "note" 或 "event"
    schedule: Optional[dict] = None  # 日程属性 JSON：{"date","time","repeat"}


class FileUpdate(BaseModel):
    name: Optional[str] = None
    content: Optional[str] = None


class FileMove(BaseModel):
    target_folder_id: str


class FolderMove(BaseModel):
    target_folder_id: Optional[str] = None  # None 表示移动到顶级目录


class ReorderRequest(BaseModel):
    type: str        # "file" 或 "folder"
    source_id: str
    target_id: str


class NoteCreate(BaseModel):
    transcript: str
    target_folder_id: Optional[str] = None  # 缺省存入"未分类"


class CommandRequest(BaseModel):
    text: str
    target_file_id: str | None = None  # 可选：当前编辑的目标文件 id（从笔记详情页发起的语音编辑）


class ConfirmRequest(BaseModel):
    confirmation_id: str
    confirmed: bool = True  # true=执行, false=取消


class ChatRequest(BaseModel):
    text: str
    conversation_id: str = ""  # 新会话传空字符串
    latitude: float | None = None   # 用户当前纬度
    longitude: float | None = None  # 用户当前经度
    device_id: str = ""  # 设备标识，用于关联用户 Profile


# ----------------------------- 用户 Profile -----------------------------


class UserPlace(BaseModel):
    name: str
    lat: float
    lon: float


class UserProfileResponse(BaseModel):
    id: str
    device_id: str
    latitude: float | None = None
    longitude: float | None = None
    home_address: str = ""
    places: list[UserPlace] = []
    created_at: str = ""
    updated_at: str = ""


class UpdateLocationRequest(BaseModel):
    latitude: float
    longitude: float


class AddPlaceRequest(BaseModel):
    name: str
    lat: float
    lon: float


# ----------------------------- 响应模型 -----------------------------


class FolderResponse(BaseModel):
    id: str
    name: str
    parent_id: Optional[str] = None
    created_at: str
    updated_at: str


class FileMetaResponse(BaseModel):
    """文件元数据（不含 content）。"""

    id: str
    name: str
    parent_id: str
    type: str = "note"  # "note" 或 "event"
    date: str = ""      # 仅 event 类型有值 YYYY-MM-DD
    time: str = ""      # 仅 event 类型有值 HH:MM
    reminder_minutes: Optional[int] = None
    recurrence: Optional[str] = None  # null/""=一次性，"daily"/"weekly"/"monthly"
    recurrence_end_date: Optional[str] = None  # 周期结束日期
    schedule: Optional[str] = None  # 日程属性 JSON 字符串
    created_at: str
    updated_at: str


class FileResponse(BaseModel):
    """文件完整信息（含 content）。"""

    id: str
    name: str
    content: str
    parent_id: str
    type: str = "note"
    date: str = ""
    time: str = ""
    reminder_minutes: Optional[int] = None
    recurrence: Optional[str] = None
    recurrence_end_date: Optional[str] = None
    schedule: Optional[str] = None  # 日程属性 JSON 字符串
    created_at: str
    updated_at: str


class MonthSummaryItem(BaseModel):
    """某日日程数量（用于日历标记）。"""

    date: str
    count: int


class FolderTreeNode(BaseModel):
    """目录树节点：文件夹信息 + 子文件夹 + 子文件。"""

    id: str
    name: str
    parent_id: Optional[str] = None
    created_at: str
    updated_at: str
    children: List["FolderTreeNode"] = []
    files: List[FileMetaResponse] = []


class CommandResult(BaseModel):
    """AI 指令统一返回结构。"""

    action: str
    success: bool
    message: str
    data: Optional[Any] = None


# 处理 FolderTreeNode 的自引用前向引用
FolderTreeNode.model_rebuild()
