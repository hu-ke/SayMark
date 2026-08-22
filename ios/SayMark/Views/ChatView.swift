import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onClose: () -> Void
    var initialMessage: String?

    @State private var inputText = ""
    @State private var sidebarOpen = false
    @State private var textEditOpen = false
    @State private var textEditContent = ""
    @State private var hasSentInitial = false
    @State private var isVoiceMode = true

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            sidebarOpen = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                    }

                    Spacer()

                    Text("AI 助手")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)

                    Spacer()

                    HStack(spacing: 14) {
                        Button {
                            viewModel.newConversation()
                        } label: {
                            TabIcon(type: "plus", size: 22, color: UIConstants.blue)
                        }

                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(UIConstants.label3)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    Color.white.opacity(0.9)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) { HDSeparator() }

                // 消息区 / 空状态
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .background(Color.white)

            // 历史会话侧边栏
            if sidebarOpen { sidebarOverlay }
            // 文字编辑底部弹窗
            if textEditOpen { textEditPanel }
        }
        .task {
            guard let msg = initialMessage, !hasSentInitial else { return }
            hasSentInitial = true
            await viewModel.send(msg)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle().fill(UIConstants.blue.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40)).foregroundColor(UIConstants.blue)
            }

            VStack(spacing: 6) {
                Text("AI 语音助手")
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.5)
                Text("直接说话或用文字告诉我你想做什么\n我会帮你整理笔记、创建日程")
                    .font(.system(size: 15)).foregroundColor(UIConstants.label3)
                    .multilineTextAlignment(.center).lineSpacing(4)
            }

            Spacer()
            inputBar
        }
    }

    // MARK: - Message List
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.messages) { msg in
                        messageRow(msg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .id(msg.id)
                    }
                    if viewModel.isStreaming {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { TypingDot(index: $0) }
                        }
                        .padding(.leading, 20).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("streaming")
                    }
                    Color.clear.frame(height: 12)
                }
            }
            .background(Color.white)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isStreaming) { _, v in
                if v { withAnimation { proxy.scrollTo("streaming", anchor: .bottom) } }
            }
            inputBar
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        VStack(spacing: 0) {
            HDSeparator()
            HStack(alignment: .bottom, spacing: 8) {
                // Left: toggle button (keyboard ↔ mic)
                Button {
                    isVoiceMode.toggle()
                } label: {
                    TabIcon(
                        type: isVoiceMode ? "keyboard" : "mic",
                        size: 26,
                        color: UIConstants.label2
                    )
                }
                .frame(width: 36, height: 36)

                // Center: voice button or text field
                if isVoiceMode {
                    Button {
                        textEditOpen = true
                        textEditContent = ""
                    } label: {
                        Text("按住 说话")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(UIConstants.label2)
                            .kerning(-0.24)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.2), lineWidth: 1))
                } else {
                    HStack {
                        TextField("输入消息...", text: $inputText)
                            .focused($isFocused)
                            .submitLabel(.send)
                            .onSubmit { sendMessage() }
                    }
                    .font(.system(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minHeight: 36)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.22), lineWidth: 1))
                }

                // Right: send button (text mode with text only, no emoji)
                if !isVoiceMode && !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UIConstants.blue))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .padding(.bottom, 28)
        }
        .background(Color(red: 0.969, green: 0.969, blue: 0.969))
    }

    // MARK: - Message Row
    @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(.system(size: 16)).foregroundColor(.white).kerning(-0.32)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UIConstants.blue)
                    .clipShape(RoundedCorner(tl: 18, tr: 18, bl: 18, br: 4))
            }
        case .thinkingGroup:
            thinkingCard(msg)
        case .thinking:
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(UIConstants.orange)
                Text(msg.content).font(.system(size: 14)).foregroundColor(UIConstants.label3)
            }
        default:
            HStack {
                Text(attributedMarkdown(msg.content))
                    .font(.system(size: 16)).foregroundColor(UIConstants.label)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                    .clipShape(RoundedCorner(tl: 18, tr: 18, bl: 4, br: 18))
                Spacer()
            }
        }
    }

    /// 将后端返回的 markdown 文本转为富文本，保证粗体/斜体/行内代码/链接/emoji 正常展示
    private func attributedMarkdown(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(text)
    }

    // MARK: - Thinking Card

    private func thinkingCard(_ msg: ChatMessage) -> some View {
        let steps = msg.steps
        let count = steps.count
        let expanded = msg.isExpanded
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { viewModel.toggleThinking(id: msg.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18)).foregroundColor(UIConstants.orange)
                    Text(msg.content.isEmpty ? "正在处理..." : msg.content)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(UIConstants.orange)
                        .lineLimit(1)
                    Spacer()
                    if count > 0 {
                        CapsuleBadge(text: "\(count)步", color: UIConstants.orange.opacity(0.14), foregroundColor: UIConstants.orange)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(UIConstants.orange)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !msg.liveText.isEmpty {
                        Text(msg.liveText)
                            .font(.system(size: 12))
                            .foregroundColor(UIConstants.orange.opacity(0.85))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 7) {
                            if i == steps.count - 1 {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(UIConstants.green)
                            } else {
                                Circle().fill(UIConstants.orange.opacity(0.7))
                                    .frame(width: 5, height: 5).padding(.top, 5)
                            }
                            Text(s)
                                .font(.system(size: 12))
                                .foregroundColor(UIConstants.orange.opacity(0.85))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: 288, alignment: .leading)
        .background(Color(red: 1, green: 0.980, blue: 0.961))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UIConstants.orange.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sidebar
    private var sidebarOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { sidebarOpen = false } }

            VStack(spacing: 0) {
                Color.clear.frame(height: 59)
                Text("历史会话").font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 20).padding(.vertical, 14)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                viewModel.switchToConversation(conv)
                                withAnimation { sidebarOpen = false }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(UIConstants.label)
                                    Text(conv.preview)
                                        .font(.system(size: 13)).foregroundColor(UIConstants.label3).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20).padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            HDSeparator().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.75)
            .background(UIConstants.card)
            .transition(.move(edge: .leading))
        }
    }

    // MARK: - Text Edit Panel
    private var textEditPanel: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { textEditOpen = false } }

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    SheetHandle()
                    HStack(spacing: 8) {
                        Button {
                            withAnimation { textEditOpen = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium)).foregroundColor(UIConstants.label3)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.fill2))
                        }
                        Spacer()
                        Text("确认文字").font(.system(size: 17, weight: .bold))
                        Spacer()
                        Button {
                            withAnimation { textEditOpen = false }
                            let t = textEditContent.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { Task { await viewModel.send(t) } }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.green))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)

                    Text(textEditContent.isEmpty
                         ? "明天下午三点产品路线图评审会议，记到日历，提前30分钟提醒。"
                         : textEditContent)
                        .font(.system(size: 16))
                        .foregroundColor(textEditContent.isEmpty ? UIConstants.label3 : UIConstants.label)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(minHeight: 110)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20).padding(.bottom, 20)
                }
                .background(UIConstants.card)
                .clipShape(RoundedCorner(tl: 20, tr: 20))
                .shadow(color: .black.opacity(0.2), radius: 48, y: -8)
                .padding(.bottom, 34)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Send
    private func sendMessage() {
        let t = inputText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        inputText = ""; isFocused = false
        Task { await viewModel.send(t) }
    }
}

// MARK: - Typing Dot
struct TypingDot: View {
    let index: Int
    @State private var animate = false
    var body: some View {
        Circle().fill(UIConstants.label3).frame(width: 8, height: 8)
            .offset(y: animate ? -5 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.2), value: animate)
            .onAppear { animate = true }
    }
}
