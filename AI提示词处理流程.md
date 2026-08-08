# SayMark AI 提示词处理流程

## 一、总体流程图

```mermaid
flowchart TD
    Start(["用户输入提示词\n(语音/文字)"]) --> Route{"哪个 API？"}

    Route -->|"POST /api/ai/command"| CmdFlow
    Route -->|"POST /api/ai/chat/stream"| ChatFlow

    subgraph CmdFlow["命令处理流程 (command endpoint)"]
        C1["接收 CommandRequest\n{ text, target_file_id }"] --> C2["command_parser.parse_command()"]
        C2 --> C3["构建目录树清单\n(_build_inventory)"]
        C3 --> C4["查询 MongoDB 获取\n所有文件夹和文件"]
        C4 --> C5["格式化目录清单文本"]
        C5 --> C6{"有 target_file_id?"}
        C6 -->|Yes| C7["加载目标文件内容\n(截断至 800 字符)"]
        C6 -->|No| C8["构建系统提示词"]
        C7 --> C8
        C8 --> C9["拼接完整系统提示词:\n- 当前日期时间\n- 目录树清单\n- 支持的动作列表\n- 时间转换规则\n- 笔记vs日程区分规则"]
        C9 --> C10["调用 Qwen LLM\n(qwen.chat, temperature=0.1)"]
        C10 --> C11["清理响应: 去除 Markdown 代码块\nJSON 解析"]
        C11 --> C12["标准化步骤\n(_normalize_steps)"]
        C12 --> C13{"needs_confirmation\n或 steps > 3?"}
        C13 -->|Yes| C14["存入待确认缓存\n返回 confirm_required"]
        C13 -->|No| C15["command_executor.execute_steps()"]
    end

    subgraph ChatFlow["聊天+隐式命令流程 (chat/stream endpoint)"]
        D1["接收 ChatRequest\n{ text, conversation_id, lat, lon, device_id }"] --> D2{"有 conversation_id?"}
        D2 -->|No| D3["生成新 UUID\n创建新对话"]
        D2 -->|Yes| D4["加载已有对话历史\n(最多 40 条消息)"]
        D3 --> D5["对话历史管理"]
        D4 --> D5
        D5 --> D6["尝试隐式命令检测\ncommand_parser.parse_command()"]
        D6 --> D7{"用户用了模糊词\n(these, that one...)?"}
        D7 -->|Yes| D8["将上轮 AI 回复\n作为上下文注入"]
        D7 -->|No| D9["直接发送给解析器"]
        D8 --> D9
        D9 --> D10["同命令流程:\n构建清单 → LLM → JSON"]
        D10 --> D11{"解析成功\n且不需要确认?"}
        D11 -->|Yes| D12["command_executor.execute_steps()"]
        D11 -->|No| D13["静默捕获异常\n转正常聊天"]
        D12 --> D14["生成 execution_note\n如: [已执行] 笔记已创建"]
        D14 --> D16["注入位置上下文"]
        D13 --> D16
        D16 --> D17{"有经纬度?"}
        D17 -->|Yes| D18["更新用户位置到 MongoDB"]
        D18 --> D19["加载用户已保存地点"]
        D19 --> D20["逆地理编码\n(geo.reverse_geocode)"]
        D20 --> D21["生成位置系统消息:\n[位置] 当前位置: xxx\n已保存的地点: [...]"]
        D17 -->|No| D22["追加用户消息到历史"]
        D21 --> D22
        D22 --> D23{"有 execution_note?"}
        D23 -->|Yes| D24["追加系统消息到历史"]
        D23 -->|No| D25["调用 Qwen LLM\n(qwen.chat_stream, temperature=0.7)"]
        D24 --> D25
        D25 --> D26["逐 token SSE 流式响应"]
        D26 --> D27["追加 assistant 回复到历史"]
        D27 --> D28(["iOS 接收 SSE:\nconversation_id → thinking → tokens → [DONE]"])
    end

    subgraph ExecFlow["步骤执行详情 (command_executor)"]
        E1["execute_steps()"] --> E2{"单步还是多步?"}
        E2 -->|单步| E3["execute()"]
        E2 -->|多步| E4["循环执行步骤"]
        E4 --> E5["_inject_created_ids()\n注入前一步创建的资源 ID"]
        E5 --> E6["execute()"]
        E6 --> E7["
            📋 Action Dispatch:
            create_note → _handle_create_note
            create_event → _handle_create_event
            append_note → _handle_append_note
            set_reminder → _handle_set_reminder
            save_place → _handle_save_place
            create_folder → _handle_create_folder
            rename → _handle_rename
            delete → _handle_delete
            move_file → _handle_move_file
            locate_folder → _handle_locate_folder
            list → _handle_list
        "]
        E7 --> E8["统一处理:\nID 优先 → 名称模糊匹配 → 执行 CRUD"]
        E8 --> E9["返回统一结果:\n{ action, success, message, data }"]
        E3 --> E8
        E4 --> E10{"步骤失败?"}
        E10 -->|Yes| E11["停止执行\n返回部分结果"]
        E10 -->|No| E12["下一条步骤"]
        E12 --> E4
        E9 --> E13(["返回执行结果"])
        E11 --> E13
    end

    C15 --> ExecFlow
    C14 --> C14End(["等待用户确认后\nPOST /api/ai/command/confirm"])
    C14End --> C15

    ExecFlow --> CmdEnd(["返回给 iOS:\n{ action, results }"])
    D12 --> ExecFlow

    style CmdFlow fill:#e1f5fe,stroke:#0288d1
    style ChatFlow fill:#f3e5f5,stroke:#7b1fa2
    style ExecFlow fill:#e8f5e9,stroke:#388e3c
```

## 二、创建笔记的详细子流程

```mermaid
flowchart TD
    Start(["create_note 动作"]) --> A["_handle_create_note()"]
    A --> B["note_generator.generate_note_with_title()"]
    B --> C["构建「笔记整理助手」系统提示词"]
    C --> D["调用 Qwen LLM\n(temperature=0.7)"]
    D --> E["LLM 返回 Markdown 文本\n第一行必须是 # 标题"]
    E --> F["extract_title()\n解析 # 标题行"]
    F --> G{"解析成功?"}
    G -->|Yes| H["使用解析出的标题"]
    G -->|No| I["使用时间戳默认名称"]
    H --> J{"有 folder_id?"}
    I --> J
    J -->|Yes| K["crud.create_file()\n保存到指定文件夹"]
    J -->|No| L["通过名称模糊匹配文件夹\ncrud.find_folders_by_name()"]
    L --> M{"匹配成功?"}
    M -->|Yes| K
    M -->|No| N["保存到用户根目录"]
    K --> O(["返回执行结果\n{ title, file_id, markdown }"])
    N --> O
```

## 三、核心文件索引

| 文件 | 职责 |
|---|---|
| `backend/app/routers/ai.py` | API 路由: `/command`, `/command/confirm`, `/chat/stream` |
| `backend/app/services/command_parser.py` | 自然语言 → JSON 步骤 (通过 LLM) |
| `backend/app/services/command_executor.py` | 执行 JSON 步骤 (MongoDB CRUD) |
| `backend/app/services/note_generator.py` | 语音转录 → Markdown 笔记 (通过 LLM) |
| `backend/app/services/qwen.py` | Qwen LLM 客户端 (OpenAI 兼容, 支持流式) |
| `backend/app/services/geo.py` | 逆地理编码 (坐标 → 地址) |
| `backend/app/crud.py` | MongoDB 数据访问层 |
