import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var sidebarOpen = false
    @State private var textEditOpen = false
    @State private var textEditContent = ""

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
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 20))
                                .foregroundColor(UIConstants.blue)
                        }

                        Button {
                            dismiss()
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
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                // 消息列表
                if viewModel.messages.isEmpty {
                    emptyChatPrompt
                } else {
                    messageList
                }
            }
            .background(Color.white)

            // 历史会话侧边栏（从左侧滑入）
            if sidebarOpen {
                sidebarOverlay
            }

            // 文字编辑底部弹窗
            if textEditOpen {
                textEditPanel
            }
        }
    }

    // MARK: - Empty Chat Prompt
    private var emptyChatPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(UIConstants.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundColor(UIConstants.blue)
            }

            VStack(spacing: 6) {
                Text("AI 语音助手")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.5)
                Text("直接说话或用文字告诉我你想做什么\n我会帮你整理笔记、创建日程")
                    .font(.system(size: 15))
                    .foregroundColor(UIConstants.label3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
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
                        MessageRow(message: msg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .id(msg.id)
                    }

                    // 流式响应指示器
                    if viewModel.isStreaming {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                TypingDot(index: i)
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("streaming-indicator")
                    }

                    Color.clear.frame(height: 12)
                }
            }
            .background(Color.white)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isStreaming) { _, newVal in
                if newVal {
                    withAnimation {
                        proxy.scrollTo("streaming-indicator", anchor: .bottom)
                    }
                }
            }

            inputBar
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 麦克风按钮
            Button {
                textEditOpen = true
                textEditContent = ""
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(UIConstants.blue))
            }

            // 文字输入
            HStack {
                if inputText.isEmpty {
                    Text("继续说话或输入...")
                        .foregroundColor(UIConstants.label3)
                }
                TextField("", text: $inputText)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(UIConstants.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(UIConstants.separator, lineWidth: 1)
            )

            // 发送按钮
            if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(UIConstants.blue))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 28)
        .background(Color.white)
        .overlay(alignment: .top) {
            HDSeparator()
        }
    }

    // MARK: - Sidebar Overlay
    private var sidebarOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarOpen = false
                    }
                }

            VStack(spacing: 0) {
                // 留出状态栏+导航栏空间
                Color.clear.frame(height: 59)

                HStack {
                    Text("历史会话")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button {
                        viewModel.newConversation()
                        withAnimation { sidebarOpen = false }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20))
                            .foregroundColor(UIConstants.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                viewModel.switchToConversation(conv)
                                withAnimation { sidebarOpen = false }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(UIConstants.label)
                                    Text(conv.preview)
                                        .font(.system(size: 13))
                                        .foregroundColor(UIConstants.label3)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            HDSeparator()
                                .padding(.leading, 20)
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
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        textEditOpen = false
                    }
                }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    SheetHandle()

                    HStack(spacing: 8) {
                        Button {
                            withAnimation { textEditOpen = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(UIConstants.label3)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.fill2))
                        }

                        Spacer()

                        Text("确认文字")
                            .font(.system(size: 17, weight: .bold))

                        Spacer()

                        Button {
                            withAnimation { textEditOpen = false }
                            if !textEditContent.trimmingCharacters(in: .whitespaces).isEmpty {
                                Task {
                                    await viewModel.send(textEditContent)
                                }
                            }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.green))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    VStack(alignment: .leading) {
                        Text(textEditContent.isEmpty ? "明天下午三点产品路线图评审会议，记到日历，提前30分钟提醒。" : textEditContent)
                            .font(.system(size: 16))
                            .foregroundColor(textEditContent.isEmpty ? UIConstants.label3 : UIConstants.label)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: 110)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(UIConstants.card)
                .clipShape(
                    RoundedCorner(topLeft: 20, topRight: 20)
                )
                .shadow(color: .black.opacity(0.2), radius: 48, y: -8)
                .padding(.bottom, 34)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Send Message
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isFocused = false
        Task {
            await viewModel.send(text)
        }
    }
}

// MARK: - Message Row
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble(message.content)
        case .thinkingGroup:
            thinkingGroupView
        case .thinking:
            thinkingLabel
        default:
            aiBubble(message.content)
        }
    }

    // MARK: - User Bubble
    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .kerning(-0.32)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(UIConstants.blue)
                .clipShape(
                    RoundedCorner(topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 4)
                )
        }
    }

    // MARK: - AI Bubble
    private func aiBubble(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(UIConstants.label)
                .kerning(-0.32)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                .clipShape(
                    RoundedCorner(topLeft: 18, topRight: 18, bottomLeft: 4, bottomRight: 18)
                )
            Spacer()
        }
    }

    // MARK: - Thinking Group
    @State private var isExpanded = false

    private var thinkingGroupView: some View {
        let steps = message.steps ?? []
        let stepCount = steps.count

        return VStack(spacing: 0) {
            // 标题卡片
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundColor(UIConstants.orange)

                    Text(isExpanded ? "正在处理..." : "处理完成（\(stepCount)步）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(UIConstants.orange)

                    Spacer()

                    CapsuleBadge(text: "\(stepCount)步",
                                 color: UIConstants.orange.opacity(0.14),
                                 foregroundColor: UIConstants.orange)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(UIConstants.orange)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(Color(red: 1.000, green: 0.980, blue: 0.961))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(UIConstants.orange.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // 展开的步骤
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, stepText in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(UIConstants.orange.opacity(0.7))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            Text(stepText)
                                .font(.system(size: 12))
                                .foregroundColor(UIConstants.orange.opacity(0.85))
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 288)
    }

    // MARK: - Thinking Label (simple)
    private var thinkingLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundColor(UIConstants.orange)
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(UIConstants.label3)
        }
    }
}

// MARK: - Typing Dot Animation
struct TypingDot: View {
    let index: Int

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(UIConstants.label3)
            .frame(width: 8, height: 8)
            .offset(y: animate ? -5 : 0)
            .animation(
                .easeInOut(duration: 0.55)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.2),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Rounded Corner Shape
struct RoundedCorner: Shape {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.size.width
        let h = rect.size.height

        path.move(to: CGPoint(x: topLeft, y: 0))
        path.addLine(to: CGPoint(x: w - topRight, y: 0))
        path.addArc(center: CGPoint(x: w - topRight, y: topRight), radius: topRight,
                    startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h - bottomRight))
        path.addArc(center: CGPoint(x: w - bottomRight, y: h - bottomRight), radius: bottomRight,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: bottomLeft, y: h))
        path.addArc(center: CGPoint(x: bottomLeft, y: h - bottomLeft), radius: bottomLeft,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: topLeft))
        path.addArc(center: CGPoint(x: topLeft, y: topLeft), radius: topLeft,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
