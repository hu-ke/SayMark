# Tasks

- [x] Task 1: 后端数据模型迁移
  - [x] SubTask 1.1: 在 `backend/setup_pg.sql` 与 `backend/sql_schema.md` 中补充 `files` 表的 `archived`、`archived_parent_id`、`archived_path` 字段说明与 ALTER 语句
  - [x] SubTask 1.2: 在 `backend/app/pg_ops.py` 的 `ensure_schema()` 中自动补齐这三个字段（`ALTER TABLE files ADD COLUMN IF NOT EXISTS ...`），并更新 `get_file` / `create_file` 等 SELECT/INSERT 语句包含新字段

- [x] Task 2: 后端归档与恢复接口
  - [x] SubTask 2.1: 在 `backend/app/pg_ops.py` 实现 `archive_file(file_id)`、`restore_file(file_id, target_folder_id=None)`、`list_archived_files()` 三个数据访问函数；归档时写入 `archived_parent_id` 与 `archived_path`（用 `get_folder_path` 拼出路径快照），恢复原处时校验原文件夹存在
  - [x] SubTask 2.2: 新增 `backend/app/routers/archive.py`，提供 `POST /api/files/{id}/archive`、`POST /api/files/{id}/restore`、`GET /api/archive`，并在原路径不存在时返回可读错误
  - [x] SubTask 2.3: 在 `backend/app/main.py` 注册 archive 路由；在 `backend/app/schemas.py` 新增 `FileRestore` 与归档列表响应模型

- [x] Task 3: 后端目录树过滤与 checklist 统计
  - [x] SubTask 3.1: 修改 `get_folder_tree` 与 `list_children`，文件查询增加 `archived=false` 过滤
  - [x] SubTask 3.2: 实现 `_todo_stats(content)` 解析 `- [ ]`/`- [x]`，在目录树/子级/单文件查询中填充 `todo_total`、`todo_done`；在 `schemas.py` 的 `FileMetaResponse` 与 `FileResponse` 中新增这两个字段

- [x] Task 4: iOS 模型与网络层
  - [x] SubTask 4.1: 在 `NoteFile.swift` 新增 `todoTotal`、`todoDone`（及归档列表模型，含 `archivedPath`）字段与解码键
  - [x] SubTask 4.2: 在 `APIClient.swift` 新增 `archiveFile`、`restoreFile`、`getArchivedFiles` 方法

- [x] Task 5: iOS 归档视图与设置入口
  - [x] SubTask 5.1: 新增 `ArchiveView.swift`，拉取 `GET /api/archive`，展示归档笔记名称与 `archived_path`，提供「恢复到原处」「移动到...」操作
  - [x] SubTask 5.2: 在 `SettingsView.swift` 新增「归档」入口行，点击进入 ArchiveView
  - [x] SubTask 5.3: 处理「原路径不存在」提示：恢复失败时弹窗引导选择其它路径（复用 FolderMoveSheet 选目录）

- [x] Task 6: iOS 笔记 checklist 勾选与清单按钮
  - [x] SubTask 6.1: 扩展 `MarkdownPreview` 解析 `- [ ]`/`- [x]` 为可交互复选框，点击切换并保存内容
  - [x] SubTask 6.2: 在 `FileDetailView` 编辑工具条新增「清单」按钮，插入 `- [x] `
  - [x] SubTask 6.3: 编辑模式下支持对 checklist 行 `[ ]`↔`[x]` 的勾选/更新

- [x] Task 7: iOS 列表进度与全部完成提示
  - [x] SubTask 7.1: 在 `FileRowCard` 右下角展示 `done/total`（仅 `todoTotal > 0` 时显示）
  - [x] SubTask 7.2: 在勾选使全部完成时弹出「已完成全部，是否移入归档」，选择「移入归档」调用归档接口

- [x] Task 8: iOS 进入笔记详情隐藏底部 Tab 栏
  - [x] SubTask 8.1: 在 `FolderTreeViewModel` 增加隐藏 Tab 栏状态，`FileDetailView` 进入时置 true、返回时置 false
  - [x] SubTask 8.2: 在 `RootView` 根据该状态隐藏 `SayMarkTabBar`

# Task Dependencies
- Task 2 依赖 Task 1
- Task 3 依赖 Task 1
- Task 4 依赖 Task 2 与 Task 3（接口与字段可用）
- Task 5 依赖 Task 4
- Task 6 依赖 Task 4
- Task 7 依赖 Task 4 与 Task 6
- Task 8 依赖 Task 4（或独立并行）
