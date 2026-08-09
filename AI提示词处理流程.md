# SayMark AI 提示词处理流程

## 一、总体流程图

```mermaid
flowchart TD
    Start(["用户输入提示词\n(语音/文字)"]) --> Route{"哪个 API？"}

    Route -->|"POST /api/ai/command"| CmdFlow
    Route -->|"POST /api/ai/chat/stream"| ChatFlow

    subgraph CmdFlow["命令处理流程 (command endpoint)"]
        C1["接收 CommandRequest\n{ text, target_file_id }"] --> C2["command_parser.parse_command()"]
        C2 --> C3["1. _build_inventory()\n构建目录树清单"]
        C3 --> C4["2. 日期引用检测\n_build_date_filtered_context()\n识别「昨天/今天/X月X号」\n预查询 MongoDB 过滤匹配文件"]
        C4 --> C5["3. 语义搜索\n_build_semantic_context()\n关键词匹配 + Embedding 向量搜索\n解决异名同义（番茄/西红柿）"]
        C5 --> C6{"有 target_file_id?"}
        C6 -->|Yes| C7["4. _build_target_context()\n加载目标文件内容（截断至 800 字符）\n注入编辑上下文"]
        C6 -->|No| C8["5. 拼接完整系统提示词"]
        C7 --> C8
        C8 --> C9["系统提示词包含:\n- 当前日期时间\n- 目录树清单（类型|id|名称|创建时间|路径）\n- 日期过滤结果（如有）\n- 语义搜索结果（如有）\n- 目标文件上下文（如有）\n- 支持的动作列表（12 种 action）\n- 相对/绝对时间换算规则\n- 笔记 vs 日程区分规则\n- 多步骤编排规则"]
        C9 --> C10["6. 调用 Qwen LLM\n(qwen.chat, temperature=0.1)"]
        C10 --> C11["7. 清理响应\n去除 Markdown 代码块 → JSON 解析\n兼容数组/单个对象输出"]
        C11 --> C12["8. _normalize_steps()\n展平嵌套 parameters → 确保 content 字段"]
        C12 --> C13["9. 安全策略\n删除操作 → 强制 needs_confirmation=true"]
        C13 --> C14{"needs_confirmation\n或 steps > 3?"}
        C14 -->|Yes| C15["存入 _pending 缓存\n返回 confirm_required\n{ confirmation_id, steps }"]
        C14 -->|No| C16["command_executor.execute_steps()"]
    end

    subgraph ChatFlow["聊天+隐式命令流程 (chat/stream endpoint)"]
        D0["接收 ChatRequest\n{ text, conversation_id, lat, lon, device_id }"]
        D0 --> D1["1. 立即 SSE 返回 conversation_id\n(status: loading)"]
        D1 --> D2{"text 为空?"}
        D2 -->|Yes| D3["返回提示并结束"]
        D2 -->|No| D4{"有 conversation_id?"}
        D4 -->|No| D5["生成新 UUID\n初始化对话历史\n注入 CHAT_SYSTEM_PROMPT"]
        D4 -->|Yes| D6["加载已有对话历史\n(最多 40 条消息)"]
        D5 --> D7["2. 检查待确认删除\n_pending_chat_deletes"]
        D6 --> D7
        D7 --> D8{"有待确认删除?"}
        D8 -->|Yes| D9{"用户回复?"}
        D9 -->|确认关键词| D10["执行删除步骤\n生成 execution_note:\n[已执行] / [执行失败]"]
        D9 -->|取消关键词| D11["生成 execution_note:\n[已取消]"]
        D9 -->|其他内容| D12["保留待确认状态\n继续正常处理"]
        D8 -->|No| D13["3. 命令解析与隐式执行"]
        D10 --> D14["跳过解析"]
        D11 --> D14
        D12 --> D13
        D13 --> D15{"含模糊指代词?\n(these, that one...)"}
        D15 -->|Yes| D16["注入上轮 AI 回复\n(_last_assistant_content)"]
        D15 -->|No| D17["直接发送给解析器"]
        D16 --> D17
        D17 --> D18["command_parser.parse_command()\n(同命令流程: 清单→LLM→JSON)"]
        D18 --> D19{"解析成功\n且 steps 存在?"}
        D19 -->|Yes| D20{"needs_confirmation\n或 steps > 3?"}
        D20 -->|Yes| D21["暂存到 _pending_chat_deletes\n生成 [待确认删除] note"]
        D20 -->|No| D22["command_executor.execute_steps()\n生成 [已执行] / [执行失败] note"]
        D19 -->|No| D23["静默捕获异常\n转正常聊天"]
        D21 --> D14
        D22 --> D14
        D23 --> D24["无 execution_note"]
        D14 --> D25["4. 位置上下文处理"]
        D24 --> D25
        D25 --> D26{"有经纬度?"}
        D26 -->|Yes| D27["update_user_location()\n更新位置到 MongoDB"]
        D27 --> D28["get_user_places()\n加载已保存地点"]
        D28 --> D29["geo.reverse_geocode()\n逆地理编码（Nominatim）"]
        D29 --> D30["生成位置系统消息:\n[位置] 用户当前在：xxx\n常用地点：[...]"]
        D26 -->|No| D31["追加 user 消息到历史"]
        D30 --> D31
        D31 --> D32{"有 execution_note?"}
        D32 -->|Yes| D33["追加系统消息到历史"]
        D32 -->|No| D34["5. 发送 thinking SSE 事件"]
        D33 --> D34
        D34 --> D35["6. 调用 Qwen LLM\n(qwen.chat_stream, temperature=0.7)"]
        D35 --> D36["逐 token SSE 流式响应\n{conversation_id} → thinking → tokens → [DONE]"]
        D36 --> D37["追加 assistant 回复到历史\n裁剪历史至 40 条"]
        D37 --> D38(["iOS 接收 SSE 完成"])
    end

    subgraph ExecFlow["步骤执行详情 (command_executor)"]
        E1["execute_steps()"] --> E2{"单步还是多步?"}
        E2 -->|单步| E3["execute()"]
        E2 -->|多步| E4["循环执行步骤"]
        E4 --> E5["_inject_created_ids()\n注入前一步创建的文件夹 id"]
        E5 --> E6["execute()"]
        E6 --> E7["
            📋 Action Dispatch:
            create_note    → _handle_create_note
            create_event   → _handle_create_event
            append_note    → _handle_append_note
            set_reminder   → _handle_set_reminder
            save_place     → _handle_save_place
            create_folder  → _handle_create_folder
            rename         → _handle_rename
            delete         → _handle_delete
            move_file      → _handle_move_file
            locate_folder  → _handle_locate_folder
            list           → _handle_list
        "]
        E7 --> E8["统一策略:\nID 优先 → 名称正则匹配 → 语义搜索兜底 → 执行"]
        E8 --> E9["创建后自动存储 Embedding 向量\n(_store_embedding)"]
        E9 --> E10["返回统一结果:\n{ action, success, message, data }"]
        E3 --> E8
        E4 --> E11{"步骤失败?"}
        E11 -->|Yes| E12["停止执行\n返回部分结果"]
        E11 -->|No| E13["下一条步骤"]
        E13 --> E4
        E10 --> E14(["返回执行结果"])
        E12 --> E14
    end

    C16 --> ExecFlow
    C15 --> C15End(["等待用户确认后\nPOST /api/ai/command/confirm\n传入 confirmation_id + confirmed: true/false"])
    C15End --> C16

    ExecFlow --> CmdEnd(["返回给 iOS:\nCommandResult { action, success, message, data }"])
    D22 --> ExecFlow

    style CmdFlow fill:#e1f5fe,stroke:#0288d1
    style ChatFlow fill:#f3e5f5,stroke:#7b1fa2
    style ExecFlow fill:#e8f5e9,stroke:#388e3c
```

## 二、命令解析子流程 (command_parser)

```mermaid
flowchart TD
    Start(["parse_command(text, target_file_id?)"]) --> A1["_build_inventory()\n拉取完整目录树\n格式: 类型|id|名称|创建时间|路径"]
    A1 --> A2{"用户文本含日期引用?\n(昨天/今天/X月X号)"}
    A2 -->|Yes| A3["_build_date_filtered_context()\n按创建日期查 MongoDB\n注入预过滤文件列表"]
    A2 -->|No| A4["日期过滤为空"]
    A3 --> A5["_build_semantic_context()\n1. 提取中文关键词(2-4字)\n2. 正则匹配文件名\n3. Embedding 语义搜索兜底\n合并结果: 关键词优先, 语义补充"]
    A4 --> A5
    A5 --> A6{"有 target_file_id?"}
    A6 -->|Yes| A7["_build_target_context()\n加载文件内容(截断800字)\n注入编辑上下文提示"]
    A6 -->|No| A8["拼接系统提示词模板"]
    A7 --> A8
    A8 --> A9["qwen.chat(temperature=0.1)"]
    A9 --> A10["_strip_code_fence()\n去除 ```json``` 包裹"]
    A10 --> A11["json.loads() 解析"]
    A11 --> A12["_normalize_steps()\n展平 parameters → 顶层字段\n确保 content 字段存在"]
    A12 --> A13["delete action?\n→ 强制 needs_confirmation=true"]
    A13 --> A14(["返回 { steps, needs_confirmation, summary }"])
```

## 三、创建笔记的详细子流程

```mermaid
flowchart TD
    Start(["create_note 动作"]) --> A["_handle_create_note()"]
    A --> B["note_generator.generate_note_with_title(content)"]
    B --> C["构建「笔记整理助手」系统提示词\n第一行必须是 # 标题\n后面用要点列出关键信息"]
    C --> D["调用 Qwen LLM\n(temperature=0.7)"]
    D --> E["LLM 返回 Markdown 文本\n第一行必须是 # 标题"]
    E --> F["extract_title()\n解析 # 标题行"]
    F --> G{"解析成功?"}
    G -->|Yes| H["使用解析出的标题作为文件名"]
    G -->|No| I["使用时间戳默认名称\n笔记_YYYYMMDD_HHMMSS"]
    H --> J["定位目标文件夹"]
    I --> J
    J --> J1{"有 target_folder_id?"}
    J1 -->|Yes| J2{"id 有效?"}
    J2 -->|Yes| J3["使用该 id"]
    J2 -->|No| J4["兜底查找"]
    J1 -->|No| J4
    J4 --> J5{"有 target_folder 名称?"}
    J5 -->|Yes| J6["名称模糊匹配文件夹\n(正则 → 未找到则用「未分类」)"]
    J5 -->|No| J7["使用「未分类」目录"]
    J6 --> K["crud.create_file()\n保存到目标文件夹"]
    J7 --> K
    J3 --> K
    K --> L["_store_embedding()\n生成 Embedding 向量\n(标题+内容前500字)"]
    L --> O(["返回 { action, success, message, data }"])
```

## 四、补充笔记的子流程 (append_note)

```mermaid
flowchart TD
    Start(["append_note 动作"]) --> A["_handle_append_note()"]
    A --> B{"有 target_id?"}
    B -->|Yes| C["crud.get_file() 加载"]
    C --> D{"文件存在?"}
    D -->|Yes| E["获取现有内容"]
    D -->|No| F["返回失败: 找不到笔记"]
    B -->|No| G{"有 name?"}
    G -->|No| H["返回失败: 缺少名称"]
    G -->|Yes| I["_resolve_files_by_name()\n1. 名称正则匹配\n2. 语义搜索兜底"]
    I --> J{"找到匹配?"}
    J -->|No| K["返回失败: 找不到笔记"]
    J -->|多条| L["返回失败: 多个匹配, 请明确"]
    J -->|单条| E
    E --> M["note_generator.merge_note()\n用 LLM 合并新旧内容\n保留原有内容, 按顺序插入"]
    M --> N["crud.update_file_content()\n更新 MongoDB"]
    N --> O["_store_embedding()\n更新 Embedding 向量"]
    O --> P(["返回 { action, success, message, data }"])
```

## 五、设置提醒的子流程 (set_reminder)

```mermaid
flowchart TD
    Start(["set_reminder 动作"]) --> A["_handle_set_reminder()"]
    A --> B["校验 minutes 参数\n(必须为整数且 >= 0)"]
    B --> C["校验 recurrence 参数\n(空/daily/weekly/monthly)"]
    C --> D{"minutes == 0?"}
    D -->|Yes| E["取消提醒\n$unset reminder 字段"]
    D -->|No| F{"有 target_id?"}
    F -->|Yes| G["crud.get_file() 加载"]
    F -->|No| H{"有 name?"}
    H -->|No| I["返回失败: 缺少名称"]
    H -->|Yes| J["_resolve_files_by_name()\n正则匹配 → 语义搜索兜底"]
    J --> K{"找到唯一匹配?"}
    K -->|No| L["返回失败"]
    K -->|Yes| G
    G --> M["crud.set_reminder()\n设置 reminder_minutes, recurrence\n可选 recurrence_end_date"]
    M --> N(["返回 { action, success, message, data }"])
    E --> N
```

## 六、删除确认子流程（聊天中的二次确认）

```mermaid
flowchart TD
    Start(["解析到 delete 步骤\nneeds_confirmation=true"]) --> A["暂存到 _pending_chat_deletes\n生成 [待确认删除] note"]
    A --> B["追加系统消息到聊天历史"]
    B --> C["LLM 告知用户:\n确认删除吗？请回复确认或取消"]
    C --> D["用户下一条消息到达"]
    D --> E{"检测确认/取消关键词?\n(确认/是的/ok/yes 或 取消/算了/不删了)"}
    E -->|确认| F["从缓存取出步骤\n执行 command_executor.execute_steps()"]
    F --> G["生成 [已执行] note"]
    E -->|取消| H["生成 [已取消] note"]
    E -->|其他| I["放回缓存\n继续正常聊天处理"]
    G --> J["追加到历史 → LLM 回复"]
    H --> J
```

## 七、核心文件索引

| 文件 | 职责 |
|---|---|
| `backend/app/routers/ai.py` | API 路由：`/command`、`/command/confirm`、`/chat/stream`，对话历史管理，待确认缓存，删除二次确认，位置上下文注入 |
| `backend/app/services/command_parser.py` | 自然语言 → JSON 步骤（通过 LLM），含目录树构建、日期过滤、语义搜索、目标文件上下文注入 |
| `backend/app/services/command_executor.py` | 执行 JSON 步骤（MongoDB CRUD），支持 11 种 action，ID 优先 → 名称匹配 → 语义搜索兜底 |
| `backend/app/services/note_generator.py` | 语音转录 → Markdown 笔记（通过 LLM），含标题提取、内容合并 |
| `backend/app/services/qwen.py` | Qwen LLM 客户端（OpenAI 兼容，支持 chat/chat_stream/embed 三种模式） |
| `backend/app/services/geo.py` | 地理编码/逆地理编码（Nominatim），Haversine 距离计算 |
| `backend/app/crud.py` | MongoDB 数据访问层，含目录树、模糊匹配、语义搜索、提醒管理、用户 Profile、Embedding 存储 |

## 八、支持的 Action 完整列表

| Action | 说明 | 关键参数 |
|---|---|---|
| `create_note` | 新建笔记（无时间点的备忘） | content, target_folder_id? |
| `create_event` | 新建日程（有时间点的安排） | title, date(YYYY-MM-DD), time(HH:MM)?, content, target_folder_id? |
| `append_note` | 补充内容到已有笔记/日程 | target_id?, name?, content |
| `set_reminder` | 设置/取消提醒（支持周期） | target_id?, name?, minutes, recurrence?, recurrence_end_date? |
| `save_place` | 保存地点到个人地名库 | name, lat, lon |
| `create_folder` | 创建文件夹（幂等） | name, parent_folder_id?, parent_folder? |
| `rename` | 重命名文件/文件夹 | type(file|folder), target_id?, name?, new_name |
| `delete` | 删除文件/文件夹（强制二次确认） | type(file|folder), target_id?, name? |
| `move_file` | 移动文件到目标目录 | file_id?, file_name?, to_folder_id?, to_folder? |
| `locate_folder` | 定位文件夹 | target_id?, name? |
| `list` | 列出目录内容 | target_folder_id?, path? |

## 九、关键设计决策

1. **两步路由**：`/command` 用于显式指令（有确认机制），`/chat/stream` 用于对话+隐式执行（静默处理失败）。
2. **目录树注入**：LLM 直接看到真实目录树的 id，通过语义选择目标，而非事后字符串匹配。
3. **日期预过滤**：用户提到「昨天/今天/X月X号」时，后端预先查 MongoDB 过滤匹配文件，避免 LLM 幻觉。
4. **语义搜索兜底**：当名称字面匹配失败时，用 Embedding 向量搜索异名同义的内容（如「番茄/西红柿」「购物相关/超市清单」）。
5. **Embedding 存储**：每次创建/更新笔记后自动生成 Embedding 向量存储到 MongoDB，供后续语义搜索使用。
6. **删除二次确认**：所有删除操作强制 `needs_confirmation=true`，在聊天中通过自然语言确认（而非 API 确认）。
7. **笔记与日程统一存储**：笔记（type=note）和日程（type=event）都存储在 MongoDB 的 files 集合中，日程额外有 date/time 字段。
8. **位置感知**：聊天接口接收经纬度，自动逆地理编码 + 加载用户常用地点，注入到 LLM 系统消息中。
9. **多步骤编排**：支持在一条指令中串联多个 action，前一步创建的文件夹 id 自动注入后续步骤。
10. **待确认缓存**：`/command` 端口的待确认步骤存内存 `_pending`，`/chat/stream` 的删除待确认存 `_pending_chat_deletes`。
