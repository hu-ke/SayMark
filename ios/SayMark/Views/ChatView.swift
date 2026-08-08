import SwiftUI

/// 聊天对话界面（气泡 + 打字机 + 多会话管理 + 语音/文字输入）
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var recognizer = SpeechRecognizer()
    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showHistory = false
    @Namespace private var bottomID

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // 消息列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if viewModel.messages.isEmpty {
                                    emptyPrompt.padding(.top, 60)
                                }
                                ForEach(viewModel.messages) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                }
                                Color.clear.frame(height: 1).id(bottomID)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            scrollToBottom(proxy)
                        }
                        .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                            scrollToBottom(proxy)
                        }
                    }

                    Divider()
                    inputBar
                }

                // 历史会话侧边栏
                if showHistory {
                    historySidebar
                }
            }
            .navigationTitle(viewModel.messages.isEmpty ? "聊天" : "聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showHistory.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.hasActiveConversation {
                        Button {
                            viewModel.newConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("好") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .alert("语音识别", isPresented: Binding(
                get: { recognizer.errorMessage != nil },
                set: { if !$0 { recognizer.errorMessage = nil } }
            )) {
                Button("好") { recognizer.errorMessage = nil }
            } message: {
                Text(recognizer.errorMessage ?? "")
            }
            .onDisappear { recognizer.stopRecording() }
        }
    }

    // MARK: - 输入栏（语音 + 文字）

    private var inputBar: some View {
        VStack(spacing: 4) {
            // 语音识别中：显示转录文字
            if recognizer.isRecording {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .opacity(recognizer.isRecording ? 1 : 0.3)
                        Text(recognizer.transcript.isEmpty ? "正在聆听..." : recognizer.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 话筒按钮
                Button {
                    Task {
                        if recognizer.isRecording {
                            recognizer.stopRecording()
                            if !recognizer.transcript.isEmpty {
                                let text = recognizer.transcript
                                viewModel.send(text)
                            }
                        } else {
                            await recognizer.startRecording()
                        }
                    }
                } label: {
                    Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(recognizer.isRecording ? .red : .accentColor)
                        .padding(.bottom, 4)
                }
                .disabled(viewModel.isStreaming)

                // 文字输入
                TextField(viewModel.isStreaming ? "AI 正在回复..." : "或输入文字...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(viewModel.isStreaming)

                // 发送按钮（有文字时显示）
                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        let text = inputText
                        inputText = ""
                        viewModel.send(text)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.accentColor)
                    }
                    .disabled(viewModel.isStreaming)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 历史会话侧边栏

    private var historySidebar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // 头部
                HStack {
                    Text("历史会话")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.newConversation()
                        showHistory = false
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if viewModel.conversations.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无历史会话")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                viewModel.switchToConversation(conv)
                                showHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conv.title)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(conv.preview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.75)
            .background(Color(.systemBackground))
            .shadow(radius: 5)

            // 右侧点击区域（点击关闭）
            Color.black.opacity(0.3)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { showHistory = false }
                }
        }
        .transition(.move(edge: .leading))
    }

    // MARK: - 空态

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("开始对话")
                .font(.headline)
            Text("你可以和我聊天，我会记住上下文。\n也可以问我关于笔记和日程的问题。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
    }
}

/// 消息气泡
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .thinking {
            thinkingBubble
        } else {
            chatBubble
        }
    }

    /// 思考过程气泡（灰色，小字，可展开）
    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 60)
        }
    }

    /// 普通对话气泡
    private var chatBubble: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.accentColor : Color.gray.opacity(0.15))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)

                if message.isStreaming {
                    HStack(spacing: 3) {
                        Circle().frame(width: 5, height: 5).opacity(0.3)
                        Circle().frame(width: 5, height: 5).opacity(0.6)
                        Circle().frame(width: 5, height: 5).opacity(1.0)
                    }
                    .padding(.leading, 4).padding(.top, 2)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
