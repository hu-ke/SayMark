import Foundation

/// 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole          // user 或 assistant
    let content: String
    let isStreaming: Bool       // true = 正在接收流式 token

    enum ChatRole {
        case user
        case assistant
    }
}

/// 聊天视图模型：管理消息列表 + SSE 流式接收 + 打字机效果
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false
    @Published var error: String?

    private var conversationId: String = ""
    /// 打字机缓冲区：收到的完整 token 在这里，逐字显示到 messages 里的 streaming message
    private var streamBuffer: String = ""
    private var typewriterTask: Task<Void, Never>?

    /// 发送用户消息，开始流式接收 AI 回复
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // 添加用户消息
        messages.append(ChatMessage(id: UUID().uuidString, role: .user, content: trimmed, isStreaming: false))

        // 添加一个空的 assistant 消息占位
        let placeholderIdx = messages.count
        messages.append(ChatMessage(id: UUID().uuidString, role: .assistant, content: "", isStreaming: true))

        streamBuffer = ""
        isStreaming = true
        error = nil

        // 启动打字机效果
        startTypewriter(at: placeholderIdx)

        // 启动 SSE 流式接收
        Task {
            await streamChat(text: trimmed, placeholderIdx: placeholderIdx)
        }
    }

    /// 启动新会话（清空消息 + conversationId）
    func newConversation() {
        typewriterTask?.cancel()
        messages = []
        conversationId = ""
        streamBuffer = ""
        isStreaming = false
    }

    // MARK: - SSE 流式接收

    private func streamChat(text: String, placeholderIdx: Int) async {
        let urlStr = "\(AppConfig.baseURL)/api/ai/chat/stream"
        guard let url = URL(string: urlStr) else {
            finishStream(placeholderIdx, error: "无效的请求地址")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "conversation_id": conversationId,
            "latitude": LocationManager.shared.latitude as Any,
            "longitude": LocationManager.shared.longitude as Any,
            "device_id": DeviceID.shared.id,
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        req.httpBody = bodyData

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))

                if payload == "[DONE]" {
                    break
                }

                // 尝试解析 JSON
                if let data = payload.data(using: .utf8) {
                    // 可能是 {"conversation_id": "xxx"} 或是纯 token 字符串
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       let cid = obj["conversation_id"] {
                        conversationId = cid
                    } else if let token = String(data: data, encoding: .utf8),
                              let unescaped = try? JSONDecoder().decode(String.self, from: data) {
                        streamBuffer += unescaped
                    }
                }
            }

            // 流结束：把打字机清空，替换为完整内容
            finishStream(placeholderIdx, error: nil)
        } catch {
            finishStream(placeholderIdx, error: error.localizedDescription)
        }
    }

    // MARK: - 打字机效果

    private func startTypewriter(at idx: Int) {
        typewriterTask?.cancel()
        var displayed = 0
        typewriterTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                let buffer = self.streamBuffer
                if buffer.count > displayed {
                    // 一次显示 1~3 个字
                    let chunkSize = min(Int.random(in: 1...3), buffer.count - displayed)
                    let idx_start = buffer.index(buffer.startIndex, offsetBy: displayed)
                    let idx_end = buffer.index(idx_start, offsetBy: chunkSize)
                    displayed += chunkSize

                    if idx < self.messages.count {
                        let newContent = String(buffer[..<idx_end])
                        self.messages[idx] = ChatMessage(
                            id: self.messages[idx].id,
                            role: .assistant,
                            content: newContent,
                            isStreaming: true
                        )
                    }
                }
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            }
        }
    }

    private func finishStream(_ idx: Int, error: String?) {
        typewriterTask?.cancel()
        isStreaming = false

        if let error = error, streamBuffer.isEmpty {
            self.error = error
            if idx < messages.count {
                messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: "[网络错误]", isStreaming: false)
            }
        } else if idx < messages.count {
            // 把打字机效果里的部分内容替换为完整内容
            messages[idx] = ChatMessage(id: messages[idx].id, role: .assistant, content: streamBuffer, isStreaming: false)
        }
        streamBuffer = ""
    }
}
