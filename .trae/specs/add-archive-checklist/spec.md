# 笔记归档与 Checklist 功能 Spec

## Why
用户需要把已完成或暂不处理的笔记归档（类似回收站），归档时保留所在路径，之后可恢复原处或转移到其它路径；同时希望笔记支持可勾选的 checklist，在列表展示完成进度，全部完成后引导归档。

## What Changes
- 后端 `files` 表新增 `archived`、`archived_parent_id`、`archived_path` 三个字段，用于归档状态、原目录引用与归档时路径快照
- 新增归档相关 REST 接口（归档、恢复原处/移动到其它路径、归档列表）；目录树与子级列表接口过滤掉已归档文件
- `FileMetaResponse` / `FileResponse` 新增 `todo_total`、`todo_done`，由 `content` 中的 `- [ ]` / `- [x]` 统计得出
- iOS 设置页新增「归档」入口；新增归档列表视图，支持恢复原处、移动到其它路径，原路径不存在时提示
- iOS 笔记详情在查看与编辑两种模式下均支持 checklist 勾选；编辑工具条新增「清单」按钮
- iOS 笔记列表 item 右下角展示 `完成/总数`（几分之几）；全部完成后弹窗提示「是否移入归档」
- iOS 进入笔记详情页时隐藏底部 Tab 栏

## Impact
- Affected specs: `voice-memo-app`（扩展 files 数据模型、笔记列表与详情编辑行为）
- Affected code:
  - 后端：`backend/app/schemas.py`、`backend/app/pg_ops.py`、`backend/app/routers/archive.py`（新增）、`backend/app/main.py`、`backend/setup_pg.sql`、`backend/sql_schema.md`
  - iOS：`ios/SayMark/Models/NoteFile.swift`、`ios/SayMark/Networking/APIClient.swift`、`ios/SayMark/Views/FolderTreeView.swift`、`ios/SayMark/Views/FileDetailView.swift`、`ios/SayMark/Views/SettingsView.swift`、`ios/SayMark/Views/RootView.swift`、新增 `ios/SayMark/Views/ArchiveView.swift`、相关 ViewModel

## ADDED Requirements

### Requirement: 文件归档字段
系统 SHALL 在 `files` 表新增归档相关字段：`archived`（BOOLEAN，默认 false）、`archived_parent_id`（原文件夹引用，文件夹删除时置 NULL）、`archived_path`（归档时所在路径的文本快照，可为空）。归档/恢复操作通过更新这些字段实现。

#### Scenario: 归档字段初始化
- **WHEN** 后端启动执行 schema 迁移
- **THEN** `files` 表存在 `archived`、`archived_parent_id`、`archived_path` 三列，旧数据默认 `archived=false`

### Requirement: 归档文件
系统 SHALL 提供将笔记移入归档的能力：归档时记录原文件夹引用与路径快照，并将文件从其所属文件夹移除（`parent_id` 置空）。

#### Scenario: 归档一个笔记
- **WHEN** 客户端调用 `POST /api/files/{id}/archive`
- **THEN** 该文件 `archived=true`、`archived_parent_id=原 parent_id`、`archived_path=归档时完整路径字符串`、`parent_id=NULL`；返回更新后的文件元数据

### Requirement: 恢复与移动归档文件
系统 SHALL 支持将归档文件恢复原处或移动到其它路径。恢复原处时若原路径已不存在，SHALL 返回可读错误提示。移动到其它路径 SHALL 传入目标文件夹。

#### Scenario: 恢复到原处（原路径存在）
- **WHEN** 客户端调用 `POST /api/files/{id}/restore` 且不带 `target_folder_id`，且 `archived_parent_id` 指向的文件夹仍存在
- **THEN** 文件 `parent_id=archived_parent_id`、`archived=false`、`archived_parent_id=NULL`、`archived_path=''`

#### Scenario: 恢复到原处（原路径不存在）
- **WHEN** 客户端调用 `POST /api/files/{id}/restore` 且不带 `target_folder_id`，但 `archived_parent_id` 为 NULL 或对应文件夹已删除
- **THEN** 返回 422/409 与「原路径不存在」提示，文件保持归档状态，供客户端引导用户选择其它路径

#### Scenario: 移动到其它路径
- **WHEN** 客户端调用 `POST /api/files/{id}/restore` 并携带 `target_folder_id`
- **THEN** 文件 `parent_id=target_folder_id`、`archived=false`、`archived_parent_id=NULL`、`archived_path=''`

### Requirement: 归档列表
系统 SHALL 提供归档文件列表接口，返回所有已归档笔记及其归档时路径快照。

#### Scenario: 查询归档列表
- **WHEN** 客户端调用 `GET /api/archive`
- **THEN** 返回所有 `archived=true` 的文件（含 `id`、`name`、`archived_path`、`created_at` 等），按归档时间倒序

### Requirement: 目录树过滤已归档文件
系统 SHALL 在普通目录树与子级列表查询中排除已归档文件。

#### Scenario: 目录树不展示已归档
- **WHEN** 客户端调用 `GET /api/folders/tree` 或查询某文件夹子级
- **THEN** 返回结果中不包含 `archived=true` 的文件

### Requirement: Checklist 统计字段
系统 SHALL 从笔记 `content` 中解析 checklist 条目（形如 `- [ ]` / `- [x]`，支持 `-` 或 `*` 前缀），在文件元数据中返回 `todo_total`（总数）与 `todo_done`（已完成数）。

#### Scenario: 统计 checklist 进度
- **WHEN** 笔记内容包含 3 个 `- [ ]` 和 2 个 `- [x]`
- **THEN** 文件元数据 `todo_total=5`、`todo_done=2`

### Requirement: iOS 归档入口与列表
iOS SHALL 在「设置」页提供「归档」入口，点击进入归档列表视图，展示已归档笔记名称与归档时路径。

#### Scenario: 打开归档列表
- **WHEN** 用户在设置页点击「归档」
- **THEN** 进入归档列表，展示归档笔记及其原路径

### Requirement: iOS 恢复与移动及提示
iOS 归档列表 SHALL 为每个归档项提供「恢复到原处」与「移动到...」操作；恢复原处时若后端返回「原路径不存在」，SHALL 弹出提示并引导用户选择其它路径。

#### Scenario: 恢复原处失败提示
- **WHEN** 用户点击「恢复到原处」且原路径不存在
- **THEN** 弹出提示（如「原路径不存在，请选择其它路径」），用户可选择「移动到...」重新选择文件夹

### Requirement: iOS 笔记 checklist 勾选
iOS 笔记详情 SHALL 在查看与编辑两种模式下均支持勾选 checklist 项：`- [ ]` / `- [x]` 以复选框展示，点击勾选/取消后更新并保存对应 markdown 内容。

#### Scenario: 查看模式勾选
- **WHEN** 用户在笔记详情（查看模式）点击某个 checklist 复选框
- **THEN** 该项状态在 `[ ]`/`[x]` 间切换，内容保存到后端，列表进度同步更新

#### Scenario: 编辑模式勾选
- **WHEN** 用户在编辑模式下对 checklist 项执行勾选操作
- **THEN** 对应 markdown 行的 `[ ]`↔`[x]` 更新并保存

### Requirement: iOS 编辑工具条清单按钮
iOS 编辑工具条 SHALL 新增「清单」按钮，点击后插入一个未勾选的 checklist 条目（`- [ ] `）。

#### Scenario: 插入清单项
- **WHEN** 用户在编辑模式点击「清单」按钮
- **THEN** 在正文末尾（或光标处）插入 `- [ ] ` 并聚焦正文

### Requirement: iOS 列表进度展示
iOS 笔记列表 item SHALL 在右下角展示 `完成数/总数`（几分之几），仅当 `todo_total > 0` 时显示。

#### Scenario: 展示进度
- **WHEN** 某笔记 `todo_total=5`、`todo_done=2`
- **THEN** 该笔记列表 item 右下角显示「2/5」

### Requirement: iOS 全部完成提示
当笔记全部 checklist 项被完成（`todo_total > 0` 且 `todo_done == todo_total`）时，iOS SHALL 弹出提示「已完成全部，是否移入归档」，提供「移入归档」与「暂不」选项。

#### Scenario: 全部完成引导归档
- **WHEN** 用户勾选最后一个未完成项使全部完成
- **THEN** 弹出「已完成全部，是否移入归档」提示；选择「移入归档」则调用归档接口，选择「暂不」则关闭提示

### Requirement: iOS 隐藏底部 Tab 栏
iOS SHALL 在进入笔记详情页时隐藏底部 Tab 栏（文件/日历/安排/闹钟/设置），返回列表时恢复显示。

#### Scenario: 进入详情隐藏 Tab 栏
- **WHEN** 用户从列表点击进入某笔记详情
- **THEN** 底部 Tab 栏隐藏；返回列表后 Tab 栏恢复

## MODIFIED Requirements

### Requirement: 文件元数据模型
`FileMetaResponse` 与 `FileResponse` SHALL 在原有字段基础上新增 `todo_total`、`todo_done` 两个整型字段（默认 0），用于承载 checklist 进度。

#### Scenario: 元数据含进度
- **WHEN** 目录树或单文件接口返回文件
- **THEN** 响应包含 `todo_total` 与 `todo_done` 字段

## REMOVED Requirements
无
