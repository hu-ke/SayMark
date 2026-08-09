import SwiftUI

/// 聊天对话界面（气泡 + 打字机 + 多会话管理 + 语音/文字输入）
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showHistory = false
    @Namespace private var bottomID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Spacing.md) {
                            if viewModel.messages.isEmpty {
                                emptyPrompt.padding(.top, 80)
                            }
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg, onToggle: {
                                    if let idx = viewModel.messages.firstIndex(where: { $0.id == msg.id }) {
                                        viewModel.messages[idx].isExpanded.toggle()
                                    }
                                })
                                .id(msg.id)
                            }
                            Color.clear.frame(height: 1).id(bottomID)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in scrollToBottom(proxy) }
                }

                Divider()
                inputBar
            }
            .navigationTitle("SayMark AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        Button { withAnimation(.easeInOut(duration: 0.25)) { showHistory.toggle() } } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        if viewModel.hasActiveConversation {
                            Button { viewModel.newConversation() } label: {
                                Image(systemName: "square.and.pencil")
                            }
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
            .sheet(isPresented: $showHistory) {
                historySheet
            }
        }
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                VoiceRecordButton(
                    onSend: { text in viewModel.send(text) }
                )
                .disabled(viewModel.isStreaming)

                TextField(viewModel.isStreaming ? "AI 正在回复..." : "输入消息...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(viewModel.isStreaming)

                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        let text = inputText
                        inputText = ""
                        viewModel.send(text)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignTokens.Color.primary)
                    }
                    .disabled(viewModel.isStreaming)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }

    // MARK: - 历史会话

    private var historySheet: some View {
        NavigationStack {
            Group {
                if viewModel.conversations.isEmpty {
                    ContentUnavailableView {
                        Label("暂无历史会话", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("开始对话后会自动保存")
                    }
                } else {
                    List {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                viewModel.switchToConversation(conv)
                                showHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                    Text(conv.title)
                                        .font(DesignTokens.Font.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(DesignTokens.Color.textPrimary)
                                    Text(conv.preview)
                                        .font(DesignTokens.Font.caption)
                                        .foregroundStyle(DesignTokens.Color.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, DesignTokens.Spacing.xs)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showHistory = false }
                }
            }
        }
    }

    // MARK: - 空态

    private var emptyPrompt: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Color.primaryBg)
                    .frame(width: 72, height: 72)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 30))
                    .foregroundStyle(DesignTokens.Color.primary)
            }
            Text("SayMark AI")
                .font(DesignTokens.Font.title2)
            Text("你可以和我聊天，我会记住上下文。\n也可以让我帮你管理笔记和日程。")
                .font(DesignTokens.Font.subheadline)
                .foregroundStyle(DesignTokens.Color.textSecondary)
                .multilineTextAlignment(.center)
            Text("试试说：「帮我整理一下今天的笔记」")
                .font(DesignTokens.Font.caption)
                .foregroundStyle(DesignTokens.Color.textTertiary)
                .padding(.top, DesignTokens.Spacing.xs)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
    }
}

// MARK: - 消息气泡

private struct MessageBubble: View {
    let message: ChatMessage
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if message.role == .thinking {
            thinkingBubble
        } else if message.role == .thinkingGroup {
            thinkingGroupCard
        } else {
            chatBubble
        }
    }

    private var thinkingGroupCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { onToggle?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: message.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Color.accent)
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Color.accent)
                        Text(message.content)
                            .font(DesignTokens.Font.caption)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                        Spacer()
                        Text("\(message.steps.count)步")
                            .font(DesignTokens.Font.caption2)
                            .foregroundStyle(DesignTokens.Color.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                if message.isExpanded {
                    if !message.liveText.isEmpty {
                        Text(message.liveText)
                            .font(DesignTokens.Font.caption2)
                            .foregroundStyle(DesignTokens.Color.accent.opacity(0.9))
                            .padding(.leading, 4)
                            .padding(.top, 2)
                    }

                    if !message.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(message.steps, id: \.self) { step in
                                Text(step)
                                    .font(DesignTokens.Font.caption2)
                                    .foregroundStyle(DesignTokens.Color.textSecondary.opacity(0.8))
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
            Spacer(minLength: 60)
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.accent)
                Text(message.content)
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 60)
        }
    }

    private var chatBubble: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? DesignTokens.Color.primary
                            : DesignTokens.Color.bgSecondary
                    )
                    .foregroundStyle(
                        message.role == .user ? .white : DesignTokens.Color.textPrimary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
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
