import SwiftUI

struct CommandInputView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let onSelectFolder: (String) -> Void

    @State private var inputText: String = ""
    @State private var resultMessage: String?
    @State private var resultSuccess: Bool = false
    @State private var isSending = false
    @State private var pendingConfirmationId: String?
    @State private var pendingConfirmationMessage: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 结果反馈
                if let resultMessage = resultMessage {
                    resultBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 提示区域
                VStack(spacing: DesignTokens.Spacing.md) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(DesignTokens.Color.primaryBg)
                            .frame(width: 64, height: 64)
                        Image(systemName: "waveform")
                            .font(.system(size: 28))
                            .foregroundStyle(DesignTokens.Color.primary)
                    }
                    Text("语音或文字输入")
                        .font(DesignTokens.Font.headline)
                    Text("你可以说：明天下午3点面试\n或：定位到工作文件夹")
                        .font(DesignTokens.Font.subheadline)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }

                // 底部输入区域
                VStack(spacing: DesignTokens.Spacing.xs) {
                    Divider()
                    HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                        VoiceRecordButton(
                            onSend: { text in inputText = text }
                        )

                        TextField("说话或输入文字...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .focused($isFocused)

                        if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                Task { await sendCommand() }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(DesignTokens.Color.primary)
                            }
                            .disabled(isSending)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .background(.regularMaterial)
            }
            .navigationTitle("语音输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: resultMessage != nil)
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

    private var resultBanner: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: resultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(resultSuccess ? DesignTokens.Color.success : DesignTokens.Color.error)
            Text(resultMessage ?? "")
                .font(DesignTokens.Font.subheadline)
            Spacer()
            Button {
                withAnimation { resultMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(
            resultSuccess
                ? DesignTokens.Color.success.opacity(0.1)
                : DesignTokens.Color.error.opacity(0.1)
        )
    }

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
            let result = try await APIClient.shared.confirmCommand(confirmationId: id, confirmed: confirmed)
            handleResult(result)
        } catch {
            resultMessage = error.localizedDescription
            resultSuccess = false
        }
    }

    private func handleResult(_ result: CommandResult) {
        withAnimation { resultMessage = result.message; resultSuccess = result.success }
        if result.success {
            inputText = ""
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
