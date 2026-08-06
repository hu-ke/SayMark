"""pydantic 请求/响应模型。

约定：ID 字段用字符串；日期用 ISO 字符串。MongoDB 文档在 crud 层完成序列化。
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


class FileUpdate(BaseModel):
    name: Optional[str] = None
    content: Optional[str] = None


class FileMove(BaseModel):
    target_folder_id: str


class NoteCreate(BaseModel):
    transcript: str
    target_folder_id: Optional[str] = None  # 缺省存入"未分类"


class CommandRequest(BaseModel):
    text: str


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
    created_at: str
    updated_at: str


class FileResponse(BaseModel):
    """文件完整信息（含 content）。"""

    id: str
    name: str
    content: str
    parent_id: str
    created_at: str
    updated_at: str


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
