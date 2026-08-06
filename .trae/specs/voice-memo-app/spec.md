# 语音记事本 App Spec

## Why
用户希望通过"说话"的方式快速记录备忘并管理笔记，省去手动输入标题和内容的麻烦。一句"明天下午3点有个线上面试"即可自动生成结构化的 markdown 笔记并归档；后续可通过语音指令对文件/文件夹进行增删改查和移动操作。

## What Changes
- 新增 iOS 客户端：录音 + 语音识别（中文）+ 文件目录树 UI + 语音/文字指令入口
- 新增 Python FastAPI 后端：提供文件/文件夹 CRUD、AI 处理、笔记生成等 REST 接口
- 新增 MongoDB 数据模型：`folders` 和 `files` 两个集合，仅存储文件内容与必要元数据
- 新增 Qwen AI 集成：两类能力 —— (1) 由语音转录文本生成 markdown 笔记；(2) 解析用户自然语言指令为结构化操作并自主执行
- 新增默认顶级目录"未分类"，新建笔记默认归档至此
- 语音/文字指令支持：定位文件夹、创建/重命名/删除文件或文件夹、跨目录移动文件

## Impact
- Affected specs: 无（首次创建）
- Affected code: 全新仓库，结构如下
  - `/backend`：FastAPI 服务、AI 服务、MongoDB 访问层、路由
  - `/ios`：iOS App 工程（SwiftUI）
  - `/backend/.env`：存放 `DASHSCOPE_API_KEY` 与 `MONGO_URI` 等（位于 backend 目录下，需加入 `.gitignore`）

## ADDED Requirements

### Requirement: 默认目录初始化
系统 SHALL 在首次启动（或检测到"未分类"目录缺失时）自动创建名为"未分类"的顶级文件夹。

#### Scenario: 首次启动
- **WHEN** 后端启动且 `folders` 集合中不存在名为"未分类"的顶级目录
- **THEN** 系统自动创建该目录，其 `parent_id` 为 `null`

### Requirement: 语音笔记生成
系统 SHALL 接收用户语音转录文本，调用 Qwen 模型生成 markdown 格式笔记（含自动生成的标题），并保存到指定文件夹（默认"未分类"）。

#### Scenario: 生成并保存笔记
- **WHEN** 客户端发送 `POST /api/notes`，body 包含 `transcript`（如"明天下午3点有个线上面试"）和可选的 `target_folder_id`
- **THEN** 后端调用 Qwen 生成 markdown，从内容中提取标题作为文件名，将文件存入对应文件夹（未指定时存入"未分类"），返回新文件元数据

### Requirement: 文件目录树结构
系统 SHALL 支持任意层级的文件夹/文件嵌套：可创建多个顶级目录，顶级目录下可建子文件或子文件夹，文件夹下可继续嵌套。

#### Scenario: 多级嵌套
- **WHEN** 用户在顶级目录 A 下创建子文件夹 B，再在 B 下创建文件 C
- **THEN** `GET /api/folders/tree` 返回的树结构正确反映 A → B → C 的层级关系

### Requirement: 文件/文件夹 CRUD
系统 SHALL 提供文件与文件夹的创建、查询、重命名、删除接口。删除文件夹时 SHALL 递归删除其下所有子项。

#### Scenario: 重命名
- **WHEN** 客户端发送 `PATCH /api/folders/{id}` 或 `PATCH /api/files/{id}`，body 含新 `name`
- **THEN** 对应记录名称更新，`updated_at` 刷新

#### Scenario: 删除文件夹
- **WHEN** 客户端发送 `DELETE /api/folders/{id}`
- **THEN** 该文件夹及其所有子孙文件夹和文件被删除

### Requirement: 跨目录移动文件
系统 SHALL 支持将文件从原目录移动到目标目录。

#### Scenario: 移动文件
- **WHEN** 客户端发送 `PUT /api/files/{id}/move`，body 含 `target_folder_id`
- **THEN** 文件 `parent_id` 更新为目标文件夹 id

### Requirement: 语音/文字指令解析与执行
系统 SHALL 接收自然语言指令（来自语音转录或文字输入），由 Qwen 解析为结构化操作 JSON，并由后端自主执行（创建笔记、创建/重命名/删除文件或文件夹、移动文件、定位文件夹等）。

#### Scenario: 定位文件夹
- **WHEN** 用户说"打开工作目录"（或文字输入）
- **THEN** 后端解析意图为 `{action: "locate_folder", folder_name: "工作"}`，返回匹配的文件夹 id 与路径；客户端跳转定位

#### Scenario: 跨目录移动（自然语言）
- **WHEN** 用户说"把工作目录里的周会笔记移到归档目录"
- **THEN** 后端解析为 `{action: "move_file", file_name: "周会笔记", from_folder: "工作", to_folder: "归档"}`，查找对应文件与目录并执行移动，返回操作结果

#### Scenario: 笔记创建（自然语言）
- **WHEN** 用户直接说一段备忘内容（无明确指令动词）
- **THEN** 后端识别为创建笔记意图，按"语音笔记生成"要求处理

### Requirement: Qwen 密钥与配置
系统 SHALL 通过 `/backend/.env` 文件读取 `DASHSCOPE_API_KEY` 与 `MONGO_URI` 等配置，密钥不得硬编码进源码。`.env` 文件 SHALL 位于 backend 目录下，并被 `.gitignore` 排除以避免泄露。

#### Scenario: 配置加载
- **WHEN** 后端启动
- **THEN** 从 `.env` 加载环境变量，缺失必需变量时启动失败并给出明确错误

### Requirement: iOS 客户端语音识别
iOS 客户端 SHALL 使用系统原生 Speech 框架（`SFSpeechRecognizer`，locale `zh-CN`）将用户语音转为文本，再提交给后端处理。

#### Scenario: 录音转写
- **WHEN** 用户按住录音按钮说话
- **THEN** 客户端实时/结束后将识别文本发送至后端对应接口

### Requirement: iOS 客户端文件树展示与编辑
iOS 客户端 SHALL 以目录树形式展示文件夹与文件，支持点击进入、重命名、删除等操作入口。

#### Scenario: 浏览与编辑
- **WHEN** 用户点击文件夹进入子级或长按某项
- **THEN** 展示子级内容或弹出重命名/删除菜单

## MODIFIED Requirements
无（首次创建）

## REMOVED Requirements
无
