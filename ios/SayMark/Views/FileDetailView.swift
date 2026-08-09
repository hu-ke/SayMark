import SwiftUI

struct FileDetailView: View {
    @StateObject private var noteVM: NoteViewModel
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editContent = ""

    // 语音编辑
    @State private var isSending = false

    // 撤回
    @State private var contentHistory: [String] = []

    init(note: NoteFile, viewModel: FolderTreeViewModel) {
        _noteVM = StateObject(wrappedValue: NoteViewModel(note: note))
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("名称", text: $editName)
                            .textFieldStyle(.roundedBorder)
                        TextEditor(text: $editContent)
                            .frame(minHeight: 320)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    }
                    .padding()
                } else {
                    if let content = noteVM.note.content, !content.isEmpty {
                        MarkdownPreview(content: content)
                            .padding()
                    } else {
                        Text("(无内容)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .overlay {
                if isSending {
                    loadingOverlay
                }
            }

            // 底部工具栏（预览模式）
            if !isEditing {
                HStack {
                    // 撤回按钮
                    if !contentHistory.isEmpty {
                        Button {
                            undoLastChange()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }

                    Spacer()

                    // 话筒按钮
                    VoiceRecordButton(
                        onSend: { text in
                            Task { await sendVoiceEdit(text: text) }
                        }
                    )

                    Spacer()

                    // 编辑按钮
                    Button {
                        editName = noteVM.note.name
                        editContent = noteVM.note.content ?? ""
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(noteVM.note.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("保存") {
                        let oldContent = noteVM.note.content ?? ""
                        Task {
                            await noteVM.save(name: editName, content: editContent)
                            await viewModel.loadTree()
                            contentHistory.append(oldContent)
                            isEditing = false
                        }
                    }
                }
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { noteVM.error != nil },
            set: { if !$0 { noteVM.error = nil } }
        )) {
            Button("好") { noteVM.error = nil }
        } message: {
            Text(noteVM.error ?? "")
        }
        .task {
            await noteVM.reload()
        }
        .onAppear { viewModel.hideFloatingButton = true }
        .onDisappear { viewModel.hideFloatingButton = false }
    }

    // MARK: - 加载状态

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在调整笔记...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.7))
    }

    // MARK: - 发送语音编辑指令

    private func sendVoiceEdit(text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        do {
            let oldContent = noteVM.note.content ?? ""
            let result = try await APIClient.shared.sendCommand(
                text: text, targetFileId: noteVM.note.id
            )
            if result.success {
                // 保存旧内容用于撤回
                contentHistory.append(oldContent)
                // 重新加载笔记显示新内容
                await noteVM.reload()
                // 刷新文件树
                await viewModel.loadTree()
            }
        } catch {
            // 静默失败
        }
    }

    // MARK: - 撤回

    private func undoLastChange() {
        guard let previousContent = contentHistory.popLast() else { return }
        Task {
            await noteVM.save(name: noteVM.note.name, content: previousContent)
            await noteVM.reload()
            await viewModel.loadTree()
        }
    }
}

// MARK: - Markdown 预览组件

private struct MarkdownPreview: View {
    let content: String

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 6) // 空行间距
        } else if trimmed.hasPrefix("### ") {
            Text(inlineFormatted(String(trimmed.dropFirst(4))))
                .font(.headline)
        } else if trimmed.hasPrefix("## ") {
            Text(inlineFormatted(String(trimmed.dropFirst(3))))
                .font(.title3)
                .fontWeight(.bold)
        } else if trimmed.hasPrefix("# ") {
            Text(inlineFormatted(String(trimmed.dropFirst(2))))
                .font(.title2)
                .fontWeight(.bold)
        } else if trimmed.hasPrefix("> ") {
            Text(inlineFormatted(String(trimmed.dropFirst(2))))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 3)
                }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(inlineFormatted(String(trimmed.dropFirst(2))))
            }
        } else if let match = trimmed.wholeMatch(of: #/^(\d+)\.\s(.+)/#) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(match.1).")
                    .fontWeight(.medium)
                Text(inlineFormatted(String(match.2)))
            }
        } else if trimmed.hasPrefix("```") {
            // 代码块标记行，忽略
            Color.clear.frame(height: 0)
        } else {
            Text(inlineFormatted(trimmed))
        }
    }

    /// 处理行内格式：**加粗**、*斜体*
    private func inlineFormatted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        // 加粗 **text** — 替换掉 ** 标记，内容加粗
        for match in text.matches(of: #/\*\*(.+?)\*\*/#) {
            let full = String(match.0)
            let inner = String(match.1)
            if let range = result.range(of: full) {
                var replacement = AttributedString(inner)
                replacement.font = Font.body.bold()
                result.replaceSubrange(range, with: replacement)
            }
        }
        // 斜体 *text* — 加粗已处理掉所有 **，剩余 * 必为斜体标记
        for match in text.matches(of: #/\*(.+?)\*/#) {
            let full = String(match.0)
            let inner = String(match.1)
            if let range = result.range(of: full) {
                var replacement = AttributedString(inner)
                replacement.font = Font.body.italic()
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
}


// MARK: - 微信风格按住录音按钮

/// 按住说话 → 松开发送 → 上滑取消/转文字
struct VoiceRecordButton: View {
    let onSend: (String) -> Void
    var onCancel: (() -> Void)? = nil

    @StateObject private var recognizer = SpeechRecognizer()

    @State private var isPressed = false
    @State private var dragOffset: CGSize = .zero

    @State private var showTextMode = false
    @State private var textModeInput = ""

    @State private var waveHeights: [CGFloat] = [16, 24, 20, 28, 18, 22]
    @State private var waveTimer: Timer?

    private let zoneThreshold: CGFloat = 60
    private let recordingDelay: Double = 0.15

    private var isRecordingActive: Bool {
        isPressed && recognizer.isRecording
    }

    private enum DragZone {
        case normal, cancel, textMode
    }

    private var currentZone: DragZone {
        guard isRecordingActive else { return .normal }
        let dx = dragOffset.width
        let dy = dragOffset.height
        if dy < -zoneThreshold {
            return dx < 0 ? .cancel : .textMode
        }
        return .normal
    }

    var body: some View {
        ZStack {
            if isPressed && !showTextMode {
                recordingOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
            if showTextMode {
                textModeOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
            micButton
        }
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .onDisappear {
            waveTimer?.invalidate()
            recognizer.stopRecording()
        }
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.title3)
            .foregroundStyle(.white)
            .padding(12)
            .background(
                Circle()
                    .fill(isRecordingActive ? Color.red : Color.accentColor)
                    .scaleEffect(isRecordingActive ? 1.25 : 1.0)
            )
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleTouchDown()
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        handleTouchUp()
                    }
            )
    }

    private var recordingOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            switch currentZone {
            case .cancel:
                cancelZoneContent
            case .textMode:
                textZoneContent
            case .normal:
                recordingZoneContent
            }
            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
        .ignoresSafeArea()
    }

    private var recordingZoneContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: waveHeights[i])
                        .animation(.easeInOut(duration: 0.3), value: waveHeights[i])
                }
            }
            .frame(height: 30)

            Text(isRecordingActive ? "松开 发送" : "准备中...")
                .font(.headline)
                .foregroundStyle(.white)

            if !recognizer.transcript.isEmpty {
                Text(recognizer.transcript)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 24)

            HStack(spacing: 48) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                    Text("松开取消").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Text("转文字").font(.caption)
                    Image(systemName: "textformat.alt").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var cancelZoneContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("松开 取消")
                .font(.headline)
                .foregroundStyle(.red)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.15)))
    }

    private var textZoneContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat.alt")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("松开 转文字")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(.green.opacity(0.15)))
    }

    private var textModeOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Button {
                        showTextMode = false
                        textModeInput = ""
                        onCancel?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Circle().fill(Color.gray.opacity(0.15)))
                    }
                    Spacer()
                    Text("确认文字").font(.headline)
                    Spacer()
                    Button {
                        let text = textModeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            onSend(text)
                        }
                        showTextMode = false
                        textModeInput = ""
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(Color.green))
                    }
                }
                TextEditor(text: $textModeInput)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2))
                    )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .ignoresSafeArea()
    }

    private func handleTouchDown() {
        guard !isPressed else { return }
        isPressed = true
        dragOffset = .zero
        startWaveAnimation()
        let delay = recordingDelay
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard isPressed else { return }
            await recognizer.startRecording()
        }
    }

    private func handleTouchUp() {
        waveTimer?.invalidate()
        let zone = currentZone
        let transcript = recognizer.transcript
        recognizer.stopRecording()
        isPressed = false
        dragOffset = .zero

        switch zone {
        case .cancel:
            onCancel?()
        case .textMode:
            textModeInput = transcript
            showTextMode = true
        case .normal:
            if !transcript.isEmpty {
                onSend(transcript)
            }
        }
    }

    private func startWaveAnimation() {
        waveTimer?.invalidate()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                waveHeights = (0..<6).map { _ in CGFloat.random(in: 10...30) }
            }
        }
    }
}
