import SwiftUI

/// Figma 风格的语音/文字指令输入界面
struct CommandInputView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let onSelectFolder: (String) -> Void

    @State private var inputText: String = ""
    @State private var resultMessage: String?
    @State private var resultSuccess: Bool = false
    @State private var isSending = false
    @State private var pendingConfirmationId: String?
    @State private var pendingConfirmationMessage: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 语音 + 文字输入区
                    HStack(spacing: 10) {
                        // 文字输入
                        HStack {
                            TextField("说话或输入文字...", text: $inputText, axis: .vertical)
                                .font(.system(size: 16))
                                .lineLimit(1...4)
                            Spacer()
                        }
                        .padding(12)
                        .background(DesignColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DesignColor.separatorLight, lineWidth: 1)
                        )

                        // 话筒按钮
                        VoiceRecordButton(
                            onSend: { text in
                                inputText = text
                            }
                        )
                    }

                    // 示例提示
                    Text("例：明天下午3点面试 / 定位到工作文件夹 / 把这条笔记移到个人")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignColor.label3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(DesignColor.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 发送按钮
                    Button {
                        Task { await sendCommand() }
                    } label: {
                        Text(isSending ? "发送中..." : "发送")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending
                                        ? DesignColor.blue.opacity(0.5)
                                        : DesignColor.blue)
                            )
                            .shadow(color: DesignColor.blue.opacity(0.3), radius: 12, y: 4)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)

                    // 结果卡片
                    if let resultMessage = resultMessage {
                        resultCard
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            .background(DesignColor.background)
            .navigationTitle("语音输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(DesignColor.blue)
                }
            }
        }
        .confirmationDialog(
            "请确认执行",
            isPresented: Binding(
                get: { pendingConfirmationId != nil },
                set: { if !$0 { pendingConfirmationId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认执行") {
                guard let cid = pendingConfirmationId else { return }
                pendingConfirmationId = nil
                Task { await runConfirmation(id: cid, confirmed: true) }
            }
            Button("取消", role: .cancel) {
                let cid = pendingConfirmationId
                pendingConfirmationId = nil
                if let cid = cid {
                    Task { await runConfirmation(id: cid, confirmed: false) }
                }
            }
        } message: {
            Text(pendingConfirmationMessage)
        }
    }

    // MARK: - 结果卡片

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(resultSuccess ? DesignColor.green : DesignColor.red)
                        .frame(width: 24, height: 24)
                    Image(systemName: resultSuccess ? "checkmark" : "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(resultSuccess ? "成功" : "失败")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(resultSuccess ? DesignColor.green : DesignColor.red)
            }
            Text(resultMessage ?? "")
                .font(.system(size: 14))
                .foregroundStyle(DesignColor.label)
                .lineSpacing(2)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(resultSuccess ? DesignColor.green.opacity(0.08) : DesignColor.red.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            (resultSuccess ? DesignColor.green : DesignColor.red).opacity(0.25),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - API

    private func sendCommand() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await APIClient.shared.sendCommand(text: text)
            if result.action == "confirm_required" {
                if let dict = result.data?.dictionaryValue,
                   let cid = dict["confirmation_id"] as? String {
                    pendingConfirmationId = cid
                    pendingConfirmationMessage = result.message
                } else {
                    resultMessage = result.message
                    resultSuccess = false
                }
                return
            }
            handleResult(result)
        } catch {
            resultMessage = error.localizedDescription
            resultSuccess = false
        }
    }

    private func runConfirmation(id: String, confirmed: Bool) async {
        isSending = true
        defer { isSending = false }
        do {
            let result = try await APIClient.shared.confirmCommand(
                confirmationId: id, confirmed: confirmed
            )
            handleResult(result)
        } catch {
            resultMessage = error.localizedDescription
            resultSuccess = false
        }
    }

    private func handleResult(_ result: CommandResult) {
        resultMessage = result.message
        resultSuccess = result.success
        if result.success {
            if result.action == "locate_folder" {
                if let dict = result.data?.dictionaryValue,
                   let folderId = dict["folder_id"] as? String {
                    onSelectFolder(folderId)
                }
            } else {
                Task { await viewModel.loadTree() }
            }
        }
    }
}

// MARK: - 微信风格按住录音按钮

private struct VoiceRecordButton: View {
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
        let dy = dragOffset.height
        if dy < -zoneThreshold { return dragOffset.width < 0 ? .cancel : .textMode }
        return .normal
    }

    var body: some View {
        ZStack {
            if isPressed && !showTextMode {
                recordingOverlay
            }
            if showTextMode {
                textModeOverlay
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
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .padding(12)
            .background(
                Circle()
                    .fill(isRecordingActive ? DesignColor.red : DesignColor.blue)
                    .shadow(color: DesignColor.blue.opacity(0.3), radius: 8, y: 2)
            )
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleTouchDown()
                        dragOffset = value.translation
                    }
                    .onEnded { _ in handleTouchUp() }
            )
    }

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
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
                .font(.system(size: 26, weight: .bold))
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
                .foregroundStyle(DesignColor.red)
            Text("松开 取消")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DesignColor.red)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(DesignColor.red.opacity(0.15)))
    }

    private var textZoneContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat.alt")
                .font(.system(size: 48))
                .foregroundStyle(DesignColor.green)
            Text("松开 转文字")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DesignColor.green)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(DesignColor.green.opacity(0.15)))
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
                            .foregroundStyle(DesignColor.label3)
                            .padding(8)
                            .background(Circle().fill(DesignColor.fill))
                    }
                    Spacer()
                    Text("确认文字").font(.headline)
                    Spacer()
                    Button {
                        let text = textModeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { onSend(text) }
                        showTextMode = false
                        textModeInput = ""
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(DesignColor.green))
                    }
                }
                TextEditor(text: $textModeInput)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(DesignColor.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignColor.separatorLight)
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
        Task {
            try? await Task.sleep(nanoseconds: UInt64(recordingDelay * 1_000_000_000))
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
        case .cancel: onCancel?()
        case .textMode:
            textModeInput = transcript
            showTextMode = true
        case .normal:
            if !transcript.isEmpty { onSend(transcript) }
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
