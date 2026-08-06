"""笔记路由：语音转录 -> markdown 笔记。"""

from fastapi import APIRouter, HTTPException

from .. import crud
from ..schemas import FileResponse, NoteCreate
from ..services import note_generator

router = APIRouter(prefix="/api/notes", tags=["notes"])


@router.post("", response_model=FileResponse)
async def create_note(body: NoteCreate):
    """根据转录文本生成 markdown 笔记并保存。

    流程：用 Qwen 把 transcript 生成 markdown；从 markdown 提取标题作为文件名
    （无标题用时间戳）；target_folder_id 缺省时存入「未分类」；返回新文件。
    """
    # 生成 markdown 与标题
    title, markdown = await note_generator.generate_note_with_title(body.transcript)
    # 解析目标目录
    if body.target_folder_id:
        try:
            folder = await crud.get_folder(body.target_folder_id)
        except ValueError as e:
            raise HTTPException(status_code=422, detail=str(e))
        if folder is None:
            raise HTTPException(status_code=404, detail="目标文件夹不存在")
        parent_id = body.target_folder_id
    else:
        uncategorized = await crud.get_default_uncategorized_folder()
        parent_id = uncategorized["id"]
    # 保存文件
    try:
        file_doc = await crud.create_file(title, markdown, parent_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    return file_doc
