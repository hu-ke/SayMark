import SwiftUI

/// Figma 风格的聊天对话界面
struct ChatView: View {
    let onClose: () -> Void
    @StateObject private var viewModel = ChatViewModel()
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
                                    MessageBubble(message: msg, onToggle: {
                                        if let idx = viewModel.messages.firstIndex(where: { $0.id == msg.id }) {
                                            viewModel.messages[idx].isExpanded.toggle()
                                        }
                                    })
                                    .id(msg.id)
                                }
                                Color.clear.frame(height: 1).id(bottomID)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showHistory.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18))
                            .foregroundStyle(DesignColor.blue)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("AI 助手")
                        .font(.system(size: 17, weight: .semibold))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if viewModel.hasActiveConversation {
                            Button {
                                viewModel.newConversation()
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 17))
                                    .foregroundStyle(DesignColor.blue)
                            }
                        }
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17))
                                .foregroundStyle(DesignColor.label3)
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
        }
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 话筒按钮
            Button {
                // 触发录音
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignColor.blue)
                        .frame(width: 36, height: 36)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
            }
            .disabled(viewModel.isStreaming)

            // 文字输入
            HStack {
                TextField(viewModel.isStreaming ? "AI 正在回复..." : "继续说话或输入...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(viewModel.isStreaming)
                    .font(.system(size: 16))

                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        let text = inputText
                        inputText = ""
                        viewModel.send(text)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(DesignColor.blue)
                                .frame(width: 28, height: 28)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DesignColor.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DesignColor.separatorLight, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 28)
        .background(Color(.systemBackground))
    }

    // MARK: - 历史会话侧边栏

    private var historySidebar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("历史会话")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button {
                        viewModel.newConversation()
                        showHistory = false
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18))
                            .foregroundStyle(DesignColor.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                if viewModel.conversations.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无历史会话")
                            .foregroundStyle(DesignColor.label3)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                viewModel.switchToConversation(conv)
                                showHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(DesignColor.label)
                                    Text(conv.preview)
                                        .font(.system(size: 13))
                                        .foregroundStyle(DesignColor.label3)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.75)
            .background(Color(.systemBackground))

            Color.black.opacity(0.3)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { showHistory = false }
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 24, x: 4)
        .transition(.move(edge: .leading))
    }

    // MARK: - 空态

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignColor.blue.opacity(0.3))
            Text("开始对话")
                .font(.title3)
                .fontWeight(.semibold)
            Text("你可以和我聊天，我会记住上下文。\n也可以问我关于笔记和日程的问题。")
                .font(.subheadline)
                .foregroundStyle(DesignColor.label3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
    }
}

// MARK: - 消息气泡（Figma 风格）

private struct MessageBubble: View {
    let message: ChatMessage
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if message.role == .thinkingGroup {
            thinkingGroupCard
        } else if message.role == .thinking {
            thinkingBubble
        } else {
            chatBubble
        }
    }

    /// 思考卡片（Figma `think-card` 风格：米黄背景 + 橙色边框）
    private var thinkingGroupCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { onToggle?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16))
                            .foregroundStyle(DesignColor.orange)
                        Text(message.content)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignColor.orange)
                        Spacer()
                        if !message.steps.isEmpty {
                            Text("\(message.steps.count)步")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignColor.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(DesignColor.orange.opacity(0.14))
                                )
                        }
                        Image(systemName: message.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignColor.orange)
                    }
                }
                .buttonStyle(.plain)

                if message.isExpanded {
                    if !message.liveText.isEmpty {
                        Text(message.liveText)
                            .font(.system(size: 12))
                            .foregroundStyle(DesignColor.orange.opacity(0.9))
                            .padding(.top, 2)
                    }

                    if !message.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(message.steps, id: \.self) { step in
                                HStack(alignment: .top, spacing: 7) {
                                    Circle()
                                        .fill(DesignColor.orange.opacity(0.3))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(step)
                                        .font(.system(size: 12))
                                        .foregroundStyle(DesignColor.orange.opacity(0.85))
                                        .lineSpacing(2)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 255/255, green: 251/255, blue: 245/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(DesignColor.orange.opacity(0.22), lineWidth: 1)
                    )
            )
            Spacer(minLength: 60)
        }
    }

    /// 思考过程气泡
    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignColor.orange)
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignColor.orange.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DesignColor.orange.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(DesignColor.orange.opacity(0.12), lineWidth: 1)
                    )
            )
            Spacer(minLength: 60)
        }
    }

    /// 对话气泡（Figma 风格：16px 字号，18px 圆角）
    private var chatBubble: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? DesignColor.blue : Color(red: 229/255, green: 229/255, blue: 234/255))
                    .foregroundStyle(message.role == .user ? .white : DesignColor.label)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .textSelection(.enabled)

                if message.isStreaming {
                    StreamingDots()
                        .padding(.leading, 6)
                        .padding(.top, 2)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - 流式输出动画点

private struct StreamingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DesignColor.label3.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .offset(y: isAnimating ? -5 : 0)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
