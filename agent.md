# AGENT.md — SayMark 项目导航

> 本文件是给 AI / 协作者的“地图”，用于快速定位代码、减少盲目搜索、节省 token。
> 阅读顺序：先看「目录结构」找模块，再看「关键文件索引」按需点开，不要全量读文件。

## ⚠️ 维护规则（必须遵守）

1. **文件增删**：新增或删除任何源文件后，必须同步更新下方「目录结构」。
2. **目录调整**：移动/重命名目录后，必须同步更新「目录结构」中的路径。
3. **代码职责变化**：某个文件的核心职责、对外接口或所属模块发生实质变化时，按需更新「关键文件索引」里的描述（纯 bug 修复、局部实现调整可不改）。
4. 更新时保持“一文件一行、只写作用、不写实现细节”，避免文件膨胀。

---

## 项目概览

- 语音记事本应用：自然语言/语音 → 笔记、安排、闹钟。
- **后端**：Python FastAPI + PostgreSQL（`backend/`）。
- **iOS 客户端**：SwiftUI（`ios/`）。
- 数据核心概念（`files.type` 三态）：`note` 笔记 / `appointment` 安排（一次性）/ `alarm` 闹钟（周期性）。

---

## 目录结构

```
backend/                         # FastAPI 后端
  app/
    main.py                      # 入口：挂载路由、CORS、lifespan
    config.py                    # 环境配置（.env 加载）
    schemas.py                   # pydantic 请求/响应模型
    pg_db.py                     # asyncpg 连接池 + 查询/序列化
    pg_ops.py                    # 数据访问层（CRUD、目录树、安排/闹钟查询）
    routers/                     # REST 路由
      ai.py                      # AI 指令 + 流式聊天（Agent 循环）
      appointments.py            # 安排（一次性）CRUD
      alarms.py                  # 闹钟（周期性）CRUD
      files.py                   # 笔记文件 CRUD（重命名/改内容/移动/删除）
      folders.py                 # 文件夹 CRUD + 目录树
      notes.py                   # 语音转录 → 笔记
      reorder.py                 # 同级排序
      geo.py / user.py           # 地理 / 用户 Profile
    services/                    # 业务与 AI
      command_parser.py          # 自然语言 → 结构化指令 JSON
      command_executor.py        # 执行指令（create/update/delete…）
      note_generator.py          # Qwen 生成 markdown 笔记
      qwen.py                    # Qwen 客户端封装
      geo.py                     # 逆地理编码
  setup_pg.sql                   # 建表 + 迁移（schema 变更看这里）
  sql_schema.md                  # 给 AI 用的数据库 schema 说明
  requirements.txt

ios/                             # SwiftUI iOS App（xcodegen 生成工程）
  project.yml                    # 工程定义（sources 为整个 SayMark 目录）
  SayMark/
    App/                         # AppConfig / SayMarkApp / UIConstants(颜色+TabBar+图标)
    Models/                      # NoteFile / Appointment / Alarm / Folder / APIResponse(TreeNode)
    Networking/APIClient.swift   # 唯一网络层（REST 方法全在这）
    Services/                    # NotificationManager / SpeechRecognizer / LocationManager / DeviceID
    ViewModels/                  # FolderTreeViewModel / ChatViewModel / NoteViewModel
    Views/
      RootView.swift             # 底部 Tab 容器（5 个 Tab + 录音蒙层）
      FolderTreeView.swift       # 文件列表（笔记目录树，含各 Row/删除/拖拽组件）
      CalendarView.swift         # 月历视图（安排）
      AppointmentsView.swift     # 安排列表（一次性）
      AlarmsView.swift           # 闹钟列表（周期性）
      FileDetailView.swift       # 详情页（笔记/安排/闹钟通用，含 MarkdownPreview 等）
      ChatView.swift             # AI 聊天
      NewItemSheet.swift         # 新建文件/文件夹
      SettingsView.swift / RenameSheet.swift / CommandInputView.swift

iOS App UI Redesign/             # 独立的 UI 原型（React/Vite，非主 App，一般无需改）
.trae/                           # spec / rules（任务规划与规则）
```

---

## 关键文件索引（按需打开）

### 后端
- **加一个新接口**：`routers/` 下对应路由 + `schemas.py` 加模型 + `pg_ops.py` 加数据方法 + `main.py` 注册路由。
- **改数据库结构**：`setup_pg.sql` + `sql_schema.md`（两者同步改）。
- **改 AI 行为**：`services/command_parser.py`（提示词/动作定义）→ `services/command_executor.py`（动作执行）→ `routers/ai.py`（Agent 提示词与 `_action_label`）。

### iOS
- **加/改接口调用**：只改 `Networking/APIClient.swift`。
- **加/改数据字段**：`Models/` 下对应模型（注意 CodingKeys 映射 snake_case）。
- **加一个 Tab**：`App/UIConstants.swift` 的 `SayMarkTabBar.tabs` + `RootView` 的 `switch selectedTab` + 对应 `Views/` 页面。
- **本地通知调度**：只改 `Services/NotificationManager.swift`。

---

## 命名约定

- `files.type` 取值：`note`（笔记）/ `appointment`（安排，一次性）/ `alarm`（闹钟，周期性）。
- 后端路由前缀：`/api/notes`、`/api/files`、`/api/appointments`、`/api/alarms`、`/api/ai`、`/api/folders`。
- iOS 模型：`NoteFile` / `Appointment` / `Alarm`；`Appointment` 与 `Alarm` 均有 `toNoteFile()` 供详情页复用。
