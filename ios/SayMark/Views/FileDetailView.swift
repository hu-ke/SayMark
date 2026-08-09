import SwiftUI

struct FileDetailView: View {
    @StateObject private var noteVM: NoteViewModel
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editContent = ""
    @State private var isSending = false
    @State private var contentHistory: [String] = []

    init(note: NoteFile, viewModel: FolderTreeViewModel) {
        _noteVM = StateObject(wrappedValue: NoteViewModel(note: note))
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing { editModeContent }
            else { previewModeContent }
        }
        .navigationTitle(isEditing ? "编辑" : noteVM.note.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("保存") { saveEdit() }.fontWeight(.semibold)
                } else {
                    Button { editName = noteVM.note.name; editContent = noteVM.note.content ?? ""; isEditing = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .alert("出错了", isPresented: Binding(get: { noteVM.error != nil }, set: { if !$0 { noteVM.error = nil } })) {
            Button("好") { noteVM.error = nil }
        } message: { Text(noteVM.error ?? "") }
        .task { await noteVM.reload() }
    }

    private var previewModeContent: some View {
        ZStack {
            ScrollView {
                if let content = noteVM.note.content, !content.isEmpty {
                    Text(content)
                        .font(DesignTokens.Font.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignTokens.Spacing.lg)
                } else {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        Spacer().frame(height: 80)
                        Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(DesignTokens.Color.textTertiary)
                        Text("暂无内容").font(DesignTokens.Font.headline).foregroundStyle(DesignTokens.Color.textSecondary)
                        Text("点击下方录音按钮用语音编辑\n或点击右上角铅笔手动编辑").font(DesignTokens.Font.subheadline).foregroundStyle(DesignTokens.Color.textTertiary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
            }
            if isSending { loadingOverlay }
        }
        .safeAreaInset(edge: .bottom) { bottomToolbar }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            if !contentHistory.isEmpty { Button { undoLastChange() } label: { Image(systemName: "arrow.uturn.backward").font(.title3) } }
            else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            VoiceRecordButton(onSend: { text in Task { await sendVoiceEdit(text: text) } })
            Spacer()
            Button { editName = noteVM.note.name; editContent = noteVM.note.content ?? ""; isEditing = true } label: { Image(systemName: "pencil").font(.title3) }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl).padding(.vertical, DesignTokens.Spacing.md)
        .background(.regularMaterial)
    }

    private var editModeContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("名称").font(DesignTokens.Font.caption).fontWeight(.medium).foregroundStyle(DesignTokens.Color.textSecondary)
                TextField("笔记名称", text: $editName).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("内容 (Markdown)").font(DesignTokens.Font.caption).fontWeight(.medium).foregroundStyle(DesignTokens.Color.textSecondary)
                TextEditor(text: $editContent).font(.body).frame(minHeight: 320).padding(DesignTokens.Spacing.xs)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm).stroke(DesignTokens.Color.dividerLight))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.md)
    }

    private var loadingOverlay: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView().scaleEffect(1.3)
            Text("AI 正在处理...").font(DesignTokens.Font.subheadline).foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(DesignTokens.Color.bgBase.opacity(0.8))
    }

    private func saveEdit() {
        let old = noteVM.note.content ?? ""
        Task { await noteVM.save(name: editName, content: editContent); await viewModel.loadTree(); contentHistory.append(old); isEditing = false }
    }
    private func sendVoiceEdit(text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        isSending = true; defer { isSending = false }
        do {
            let old = noteVM.note.content ?? ""
            if (try await APIClient.shared.sendCommand(text: t, targetFileId: noteVM.note.id)).success {
                contentHistory.append(old); await noteVM.reload(); await viewModel.loadTree()
            }
        } catch {}
    }
    private func undoLastChange() {
        guard let prev = contentHistory.popLast() else { return }
        Task { await noteVM.save(name: noteVM.note.name, content: prev); await noteVM.reload(); await viewModel.loadTree() }
    }
}

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
    private var isRecordingActive: Bool { isPressed && recognizer.isRecording }
    private enum DragZone { case normal, cancel, textMode }
    private var currentZone: DragZone {
        guard isRecordingActive else { return .normal }
        let dx = dragOffset.width; let dy = dragOffset.height
        if dy < -zoneThreshold { return dx < 0 ? .cancel : .textMode }
        return .normal
    }
    var body: some View {
        ZStack {
            if isPressed && !showTextMode { recordingOverlay.transition(.opacity.animation(.easeInOut(duration: 0.2))) }
            if showTextMode { textModeOverlay.transition(.opacity.animation(.easeInOut(duration: 0.2))) }
            micButton
        }
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .onDisappear { waveTimer?.invalidate(); recognizer.stopRecording() }
    }
    private var micButton: some View {
        Image(systemName: "mic.fill").font(.title3).foregroundStyle(.white).padding(12)
            .background(Circle().fill(isRecordingActive ? Color.red : DesignTokens.Color.primary).scaleEffect(isRecordingActive ? 1.25 : 1.0))
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in handleTouchDown(); dragOffset = .zero }.onEnded { _ in handleTouchUp() })
    }
    private var recordingOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            switch currentZone { case .cancel: cancelZoneContent; case .textMode: textZoneContent; case .normal: recordingZoneContent }
            Spacer().frame(height: 80)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.4)).ignoresSafeArea()
    }
    private var recordingZoneContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) { ForEach(0..<6, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.9)).frame(width: 3, height: waveHeights[i]).animation(.easeInOut(duration: 0.3), value: waveHeights[i]) } }.frame(height: 30)
            Text(isRecordingActive ? "松开 发送" : "准备中...").font(.headline).foregroundStyle(.white)
            if !recognizer.transcript.isEmpty { Text(recognizer.transcript).font(.body).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 40) }
            Spacer().frame(height: 24)
            HStack(spacing: 48) {
                HStack(spacing: 4) { Image(systemName: "xmark.circle.fill").font(.caption); Text("松开取消").font(.caption) }.foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 4) { Text("转文字").font(.caption); Image(systemName: "textformat.alt").font(.caption) }.foregroundStyle(.white.opacity(0.6))
            }
        }
    }
    private var cancelZoneContent: some View {
        VStack(spacing: 12) { Image(systemName: "xmark.circle.fill").font(.system(size: 48)).foregroundStyle(.red); Text("松开 取消").font(.headline).foregroundStyle(.red) }.padding(24).background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.15)))
    }
    private var textZoneContent: some View {
        VStack(spacing: 12) { Image(systemName: "textformat.alt").font(.system(size: 48)).foregroundStyle(.green); Text("松开 转文字").font(.headline).foregroundStyle(.green) }.padding(24).background(RoundedRectangle(cornerRadius: 16).fill(.green.opacity(0.15)))
    }
    private var textModeOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Button { showTextMode = false; textModeInput = ""; onCancel?() } label: { Image(systemName: "xmark").font(.body).foregroundStyle(.secondary).padding(8).background(Circle().fill(Color.gray.opacity(0.15))) }
                    Spacer(); Text("确认文字").font(.headline); Spacer()
                    Button { let t = textModeInput.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { onSend(t) }; showTextMode = false; textModeInput = "" } label: { Image(systemName: "checkmark").font(.body).foregroundStyle(.white).padding(8).background(Circle().fill(Color.green)) }
                }
                TextEditor(text: $textModeInput).frame(minHeight: 100).padding(8).background(Color.gray.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            }.padding(20).background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(radius: 10)).padding(.horizontal, 20).padding(.bottom, 80)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.3)).ignoresSafeArea()
    }
    private func handleTouchDown() {
        guard !isPressed else { return }
        isPressed = true; dragOffset = .zero; startWaveAnimation()
        Task { try? await Task.sleep(nanoseconds: UInt64(recordingDelay * 1_000_000_000)); guard isPressed else { return }; await recognizer.startRecording() }
    }
    private func handleTouchUp() {
        waveTimer?.invalidate(); let zone = currentZone; let t = recognizer.transcript
        recognizer.stopRecording(); isPressed = false; dragOffset = .zero
        switch zone { case .cancel: onCancel?(); case .textMode: textModeInput = t; showTextMode = true; case .normal: if !t.isEmpty { onSend(t) } }
    }
    private func startWaveAnimation() {
        waveTimer?.invalidate(); waveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in DispatchQueue.main.async { waveHeights = (0..<6).map { _ in CGFloat.random(in: 10...30) } } }
    }
}
