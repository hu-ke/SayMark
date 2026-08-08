import SwiftUI

struct CommandInputView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let onSelectFolder: (String) -> Void

    @State private var inputText: String = ""
    @State private var resultMessage: String?
    @State private var resultSuccess: Bool = false
    @State private var isSending = false
    @StateObject private var recognizer = SpeechRecognizer()
    /// 待确认指令：收到 confirm_required 时暂存 confirmation_id 与提示文案
    @State private var pendingConfirmationId: String?
    @State private var pendingConfirmationMessage: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    TextField("说话或输入文字，例如：明天下午3点面试 / 定位到工作文件夹", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        Task {
                            if recognizer.isRecording {
                                recognizer.stopRecording()
                                if !recognizer.transcript.isEmpty {
                                    inputText = recognizer.transcript
                                }
                            } else {
                                await recognizer.startRecording()
                            }
                        }
                    } label: {
                        Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(recognizer.isRecording ? Color.red : Color.accentColor)
                    }
                }
                .padding(.horizontal)

                if recognizer.isRecording {
                    Text(recognizer.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                Button {
                    Task { await sendCommand() }
                } label: {
                    Text(isSending ? "发送中..." : "发送")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .padding(.horizontal)

                if let resultMessage = resultMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: resultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(resultSuccess ? .green : .red)
                            Text(resultSuccess ? "成功" : "失败")
                                .font(.headline)
                        }
                        Text(resultMessage)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("语音输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { recognizer.stopRecording(); dismiss() }
                }
            }
            .onDisappear { recognizer.stopRecording() }
            .alert("出错了", isPresented: Binding(
                get: { recognizer.errorMessage != nil },
                set: { if !$0 { recognizer.errorMessage = nil } }
            )) {
                Button("好") { recognizer.errorMessage = nil }
            } message: {
                Text(recognizer.errorMessage ?? "")
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
    }

    private func sendCommand() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await APIClient.shared.sendCommand(text: text)
            // 需要确认：弹框让用户确认
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

    /// 统一处理执行结果（展示文案 + 刷新/定位）
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
