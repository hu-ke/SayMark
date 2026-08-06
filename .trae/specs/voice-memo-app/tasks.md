# Tasks

- [x] Task 1: 初始化后端工程结构与依赖
  - [x] SubTask 1.1: 创建 `/backend` 目录，初始化 FastAPI 工程（`main.py`、`requirements.txt`、`app` 包结构）
  - [x] SubTask 1.2: 配置 `/backend/.env` 加载（`python-dotenv`），定义 `DASHSCOPE_API_KEY`、`MONGO_URI`、`MONGO_DB_NAME`、`QWEN_MODEL` 等变量；创建 `/backend/.env.example`（不含真实密钥）；将 `/backend/.env` 加入 `.gitignore`
  - [x] SubTask 1.3: 接入 MongoDB（`motor`），实现启动时自动创建"未分类"顶级目录的逻辑

- [x] Task 2: 数据模型与访问层
  - [x] SubTask 2.1: 定义 `folders` 集合结构：`{ _id, name, parent_id, created_at, updated_at }`
  - [x] SubTask 2.2: 定义 `files` 集合结构：`{ _id, name, content, parent_id, created_at, updated_at }`
  - [x] SubTask 2.3: 实现数据访问层（CRUD + 递归删除子树 + 目录树查询 + 按名称/父级查找）

- [x] Task 3: 文件/文件夹 REST 接口
  - [x] SubTask 3.1: 文件夹接口 `GET /api/folders/tree`、`POST /api/folders`、`PATCH /api/folders/{id}`、`DELETE /api/folders/{id}`
  - [x] SubTask 3.2: 文件接口 `GET /api/files/{id}`、`POST /api/files`、`PATCH /api/files/{id}`、`DELETE /api/files/{id}`、`PUT /api/files/{id}/move`
  - [x] SubTask 3.3: 笔记生成接口 `POST /api/notes`（接收 transcript 与可选 target_folder_id）

- [x] Task 4: Qwen AI 服务集成
  - [x] SubTask 4.1: 封装 Qwen 调用客户端（通过 DashScope OpenAI 兼容接口），从 `.env` 读取密钥与模型名
  - [x] SubTask 4.2: 实现笔记生成 Prompt：输入转录文本 → 输出 markdown（含标题），并在后端从结果中提取标题作为文件名
  - [x] SubTask 4.3: 实现指令解析 Prompt：输入自然语言 → 输出结构化 JSON（action 及参数），覆盖 `create_note`/`create_folder`/`rename`/`delete`/`move_file`/`locate_folder`/`list` 等动作
  - [x] SubTask 4.4: 实现指令执行编排：根据解析结果调用对应数据访问层方法，返回执行结果（含定位信息或错误）

- [x] Task 5: AI 指令路由
  - [x] SubTask 5.1: `POST /api/ai/command` 接收 `{ text }`，调用 Task 4.3/4.4 完成解析与执行，返回统一结果对象
  - [x] SubTask 5.2: 处理歧义/未找到场景（如文件夹不存在、文件名重复），返回可读错误信息供客户端展示

- [x] Task 6: iOS 客户端工程初始化
  - [x] SubTask 6.1: 创建 `/ios` SwiftUI 工程，配置 Info.plist 语音识别与麦克风权限（`NSSpeechRecognitionUsageDescription`、`NSMicrophoneUsageDescription`）
  - [x] SubTask 6.2: 配置后端 Base URL（可放 `Info.plist` 或 `Configuration`），封装网络层（URLSession）

- [x] Task 7: iOS 语音录入与识别
  - [x] SubTask 7.1: 实现 `SpeechRecognizer` 服务（`SFSpeechRecognizer` zh-CN + `SFSpeechAudioBufferRecognitionRequest`）
  - [x] SubTask 7.2: 录音 UI（按住说话 / 点击录音），实时/结束后获取识别文本

- [x] Task 8: iOS 文件目录树 UI
  - [x] SubTask 8.1: 实现 `FolderTreeViewModel`，拉取 `GET /api/folders/tree` 并构建可展开的树形数据
  - [x] SubTask 8.2: 实现目录树视图（`List` + `DisclosureGroup`），点击文件夹进入子级，点击文件查看内容
  - [x] SubTask 8.3: 实现文件/文件夹重命名、删除、新建、移动的操作入口与对应接口调用

- [x] Task 9: iOS 笔记生成与指令入口
  - [x] SubTask 9.1: 录音结束 → 调用 `POST /api/notes` 生成笔记并在 UI 刷新目录树
  - [x] SubTask 9.2: 提供"指令"输入框（文字）+ 语音指令按钮，调用 `POST /api/ai/command`，根据返回结果（如定位文件夹）更新 UI

- [x] Task 10: 端到端联调与验证
  - [x] SubTask 10.1: 验证"说一句话生成笔记并存入未分类"全流程
  - [x] SubTask 10.2: 验证语音/文字指令的定位、移动、增删改查场景
  - [x] SubTask 10.3: 验证多级目录嵌套与递归删除

# Task Dependencies
- Task 2 依赖 Task 1
- Task 3 依赖 Task 2
- Task 4 依赖 Task 1（配置）与 Task 2（数据访问层）
- Task 5 依赖 Task 4 与 Task 3
- Task 7 依赖 Task 6
- Task 8 依赖 Task 6 与 Task 3（接口可用）
- Task 9 依赖 Task 7、Task 8、Task 5
- Task 10 依赖 Task 5 与 Task 9
