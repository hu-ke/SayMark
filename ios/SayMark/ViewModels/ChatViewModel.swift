import Foundation

/// 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole
    let content: String
    let isStreaming: Bool
    let isThinking: Bool
    var steps: [String]          // 思考步骤（thinkingGroup 用）
    var isExpanded: Bool         // 是否展开思考卡片
    var liveText: String         // 实时打字机文本（thinkingGroup 用）

    enum ChatRole {
        case user
        case assistant
        case thinking             // 单条思考步骤（兼容旧格式）
        case thinkingGroup        // 可折叠思考卡片
    }
}

/// 会话元数据
struct ConversationMeta: Identifiable, Equatable {
    let id: String
    var title: String
    var preview: String
}

/// 聊天视图模型：多会话 + 真正流式输出 + 思考过程可见
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var conversations: [ConversationMeta] = []
    @Published var isStreaming = false
    @Published var error: String?

    private var currentConversationId: String = ""
    private var typewriterTask: Task<Void, Never>?
    private var currentStreamTask: Task<Void, Never>?
    private var pendingStepFullText: String?
    private var currentThinkingId: String?  // 当前轮次的思考卡片 id（每轮独立）

    var hasActiveConversation: Bool { !currentConversationId.isEmpty }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // 取消上一个流（如果有）
        currentStreamTask?.cancel()

        if currentConversationId.isEmpty {
            currentConversationId = UUID().uuidString
            let title = String(trimmed.prefix(20))
            conversations.insert(ConversationMeta(id: currentConversationId, title: title, preview: trimmed), at: 0)
        }

        messages.append(ChatMessage(id: UUID().uuidString, role: .user, content: trimmed, isStreaming: false, isThinking: false, steps: [], isExpanded: true, liveText: ""))

        isStreaming = true
        error = nil
        currentThinkingId = nil  // 新一轮对话：使用独立的思考卡片

        currentStreamTask = Task { await streamChat(text: trimmed) }
    }

    func switchToConversation(_ conv: ConversationMeta) {
        guard conv.id != currentConversationId, !isStreaming else { return }
        currentStreamTask?.cancel()
        typewriterTask?.cancel()
        pendingStepFullText = nil
        currentThinkingId = nil
        currentConversationId = conv.id
        messages = []
        isStreaming = false
    }

    func newConversation() {
        currentStreamTask?.cancel()
        typewriterTask?.cancel()
        pendingStepFullText = nil
        currentThinkingId = nil
        currentConversationId = ""
        messages = []
        isStreaming = false
    }

    /// 展开/折叠某条思考卡片
    func toggleThinking(id: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        var msg = messages[idx]
        msg.isExpanded.toggle()
        messages[idx] = msg
    }

    // MARK: - 真正的流式接收（token 到了立刻显示）

    private func streamChat(text: String) async {
        var streamConvId = currentConversationId  // 捕获当前会话 ID，防止切换会话后旧内容漏入
        let urlStr = "\(AppConfig.baseURL)/api/ai/chat/stream"
        guard let url = URL(string: urlStr) else {
            finishStream(error: "无效的请求地址")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "conversation_id": currentConversationId,
            "latitude": LocationManager.shared.latitude as Any,
            "longitude": LocationManager.shared.longitude as Any,
            "device_id": DeviceID.shared.id,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            var fullResponse = ""

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                // 如果用户切换/新建了会话，丢弃当前流的所有后续内容
                guard currentConversationId == streamConvId else { break }
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8) else { continue }

                // 解析 conversation_id（可能包含 status 字段）
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let cid = obj["conversation_id"] {
                    currentConversationId = cid
                    streamConvId = cid  // 同步捕获的 ID，首次消息时后端会返回新 UUID
                    if let idx = conversations.firstIndex(where: { $0.id == currentConversationId || $0.id.isEmpty }) {
                        conversations[idx] = ConversationMeta(id: cid, title: conversations[idx].title, preview: conversations[idx].preview)
                    }
                    // status: 'loading' → 思考卡片会在后续进度事件中自动出现
                    if obj["status"] == "loading" {
                        // 不再创建空加载气泡，思考卡片本身就是进度反馈
                        continue
                    }
                    continue
                }

                // 解析结构化 thinking 事件（每轮独立一张思考卡片）
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let title = obj["thinking_start"] as? String {
                        if currentThinkingId == nil {
                            let card = ChatMessage(id: UUID().uuidString, role: .thinkingGroup, content: title, isStreaming: false, isThinking: true, steps: [], isExpanded: true, liveText: "")
                            messages.append(card)
                            currentThinkingId = card.id
                        }
                        continue
                    }
                    if let stepText = obj["thinking_step"] as? String {
                        startTypewriterStep(stepText)
                        continue
                    }
                    if let _ = obj["thinking_end"] {
                        typewriterTask?.cancel()
                        if let id = currentThinkingId,
                           let idx = messages.firstIndex(where: { $0.id == id }) {
                            if let lastStep = messages[idx].steps.last,
                               let full = pendingStepFullText,
                               lastStep.isEmpty || lastStep.count < full.count {
                                messages[idx].steps[messages[idx].steps.count - 1] = full
                            }
                            let count = messages[idx].steps.count
                            messages[idx] = ChatMessage(id: id, role: .thinkingGroup, content: "处理完成（\(count)步）", isStreaming: false, isThinking: true, steps: messages[idx].steps, isExpanded: false, liveText: "")
                        }
                        pendingStepFullText = nil
                        currentThinkingId = nil
                        continue
                    }
                    // 服务端逐字发送的思考实时文本（打字机效果）
                    if let thinkingText = obj["thinking_text"] as? String {
                        if let id = currentThinkingId,
                           let idx = messages.firstIndex(where: { $0.id == id }) {
                            messages[idx].liveText = thinkingText
                        } else {
                            let card = ChatMessage(id: UUID().uuidString, role: .thinkingGroup, content: "正在处理...", isStreaming: false, isThinking: true, steps: [], isExpanded: true, liveText: thinkingText)
                            messages.append(card)
                            currentThinkingId = card.id
                        }
                        continue
                    }
                    // 兼容旧格式
                    if let thinking = obj["thinking"] as? String {
                        messages.append(ChatMessage(id: UUID().uuidString, role: .thinking, content: thinking, isStreaming: false, isThinking: true, steps: [], isExpanded: true, liveText: ""))
                        continue
                    }
                }

                // 普通 token：直接追加显示
                if let token = String(data: data, encoding: .utf8),
                   let unescaped = try? JSONDecoder().decode(String.self, from: data) {
                    fullResponse += unescaped

                    // 第一个 token 到达时：如果有空占位消息则替换，否则创建
                    if fullResponse.count == unescaped.count {
                        if let idx = messages.lastIndex(where: { $0.isStreaming && $0.role == .assistant && $0.content.isEmpty }) {
                            // 替换之前的加载占位
                            messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: unescaped, isStreaming: true, isThinking: false, steps: [], isExpanded: true, liveText: "")
                        } else {
                            messages.append(ChatMessage(id: UUID().uuidString, role: .assistant, content: unescaped, isStreaming: true, isThinking: false, steps: [], isExpanded: true, liveText: ""))
                        }
                    } else {
                        // 更新已有消息
                        if let idx = messages.lastIndex(where: { $0.isStreaming && $0.role == .assistant }) {
                            messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: fullResponse, isStreaming: true, isThinking: false, steps: [], isExpanded: true, liveText: "")
                        }
                    }
                }
            }

            // 完成：把最后一条标记为非流式
            if let idx = messages.lastIndex(where: { $0.isStreaming && $0.role == .assistant }) {
                messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: messages[idx].content, isStreaming: false, isThinking: false, steps: [], isExpanded: true, liveText: "")
            }
            // 更新预览
            if let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) {
                let preview = String(fullResponse.prefix(30))
                conversations[idx] = ConversationMeta(id: conversations[idx].id, title: conversations[idx].title, preview: preview)
            }
            // 聊天可能创建/修改了日程与提醒，重新调度本地通知
            await NotificationManager.shared.refreshFromServer()
            finishStream(error: nil)
        } catch {
            finishStream(error: error.localizedDescription)
        }
    }

    private func finishStream(error: String?) {
        typewriterTask?.cancel()
        pendingStepFullText = nil
        currentThinkingId = nil
        isStreaming = false
        if let error = error {
            self.error = error
            // 把最后一条流式消息改为错误
            if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                messages[idx] = ChatMessage(id: messages[idx].id, role: messages[idx].role, content: messages[idx].content, isStreaming: false, isThinking: false, steps: [], isExpanded: true, liveText: "")
            }
        }
    }

    // MARK: - 步骤打字机效果

    /// 逐步显示思考步骤文本，产生打字机效果
    private func startTypewriterStep(_ fullText: String) {
        guard let thinkingId = currentThinkingId,
              let idx = messages.firstIndex(where: { $0.id == thinkingId }) else { return }

        // 先取消上一个步骤的打字机任务
        typewriterTask?.cancel()

        // 确保上一步完整展示（如果之前有被打断的步骤）
        if let pending = pendingStepFullText,
           let lastStep = messages[idx].steps.last,
           lastStep.count < pending.count {
            messages[idx].steps[messages[idx].steps.count - 1] = pending
        }

        // 将新步骤以空字符串占位加入
        messages[idx].steps.append("")
        let stepIndex = messages[idx].steps.count - 1
        let msgId = thinkingId
        pendingStepFullText = fullText

        typewriterTask = Task {
            var revealed = ""
            for char in fullText {
                guard !Task.isCancelled else { return }
                revealed.append(char)
                if let idx2 = messages.firstIndex(where: { $0.id == msgId }),
                   stepIndex < messages[idx2].steps.count {
                    messages[idx2].steps[stepIndex] = revealed
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
    }
}
