import Foundation

/// 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole
    let content: String
    let isStreaming: Bool        // true = 正在接收流式 token
    let isThinking: Bool         // true = 思考过程消息

    enum ChatRole {
        case user
        case assistant
        case thinking             // 思考中 → 显示执行结果/分析过程
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

    var hasActiveConversation: Bool { !currentConversationId.isEmpty }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        if currentConversationId.isEmpty {
            currentConversationId = UUID().uuidString
            let title = String(trimmed.prefix(20))
            conversations.insert(ConversationMeta(id: currentConversationId, title: title, preview: trimmed), at: 0)
        }

        messages.append(ChatMessage(id: UUID().uuidString, role: .user, content: trimmed, isStreaming: false, isThinking: false))

        isStreaming = true
        error = nil

        Task { await streamChat(text: trimmed) }
    }

    func switchToConversation(_ conv: ConversationMeta) {
        guard conv.id != currentConversationId, !isStreaming else { return }
        typewriterTask?.cancel()
        currentConversationId = conv.id
        messages = []
        isStreaming = false
    }

    func newConversation() {
        typewriterTask?.cancel()
        currentConversationId = ""
        messages = []
        isStreaming = false
    }

    // MARK: - 真正的流式接收（token 到了立刻显示）

    private func streamChat(text: String) async {
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
            var thinkingInserted = false

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8) else { continue }

                // 解析 conversation_id
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let cid = obj["conversation_id"] {
                    currentConversationId = cid
                    if let idx = conversations.firstIndex(where: { $0.id == currentConversationId || $0.id.isEmpty }) {
                        conversations[idx] = ConversationMeta(id: cid, title: conversations[idx].title, preview: conversations[idx].preview)
                    }
                    continue
                }

                // 解析 thinking 消息（后端发出，展示思考过程）
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let thinking = obj["thinking"] {
                    messages.append(ChatMessage(id: UUID().uuidString, role: .thinking, content: thinking, isStreaming: false, isThinking: true))
                    thinkingInserted = true
                    continue
                }

                // 普通 token：直接追加显示
                if let token = String(data: data, encoding: .utf8),
                   let unescaped = try? JSONDecoder().decode(String.self, from: data) {
                    fullResponse += unescaped

                    // 第一个 token 到达时创建 assistant 消息
                    if fullResponse.count == unescaped.count {
                        messages.append(ChatMessage(id: UUID().uuidString, role: .assistant, content: unescaped, isStreaming: true, isThinking: false))
                    } else {
                        // 更新已有消息
                        if let idx = messages.lastIndex(where: { $0.isStreaming && $0.role == .assistant }) {
                            messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: fullResponse, isStreaming: true, isThinking: false)
                        }
                    }
                }
            }

            // 完成：把最后一条标记为非流式
            if let idx = messages.lastIndex(where: { $0.isStreaming && $0.role == .assistant }) {
                messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: messages[idx].content, isStreaming: false, isThinking: false)
            }
            // 更新预览
            if let idx = conversations.firstIndex(where: { $0.id == currentConversationId }) {
                let preview = String(fullResponse.prefix(30))
                conversations[idx] = ConversationMeta(id: conversations[idx].id, title: conversations[idx].title, preview: preview)
            }
            finishStream(error: nil)
        } catch {
            finishStream(error: error.localizedDescription)
        }
    }

    private func finishStream(error: String?) {
        typewriterTask?.cancel()
        isStreaming = false
        if let error = error {
            self.error = error
            // 把最后一条流式消息改为错误
            if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                messages[idx] = ChatMessage(id: messages[idx].id, role: messages[idx].role, content: messages[idx].content, isStreaming: false, isThinking: false)
            }
        }
    }
}
