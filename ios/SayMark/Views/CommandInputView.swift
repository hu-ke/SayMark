import SwiftUI

struct CommandInputView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let onSelectFolder: (String) -> Void

    @State private var inputText: String = ""
    @State private var resultMessage: String?
    @State private var resultSuccess: Bool = false
    @State private var isSending = false
    @StateObject private var recognizer = SpeechRecognizer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    TextField("输入指令，例如：定位到 xxx 文件夹", text: $inputText, axis: .vertical)
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
                            .foregroundStyle(recognizer.isRecording ? .red : .tint)
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
            .navigationTitle("指令")
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
        }
    }

    private func sendCommand() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await APIClient.shared.sendCommand(text: text)
            resultMessage = result.message
            resultSuccess = result.success
            if result.success {
                if result.action == "locate_folder" {
                    // 读取 data.folder_id 并通知 RootView 定位
                    if let dict = result.data?.dictionaryValue,
                       let folderId = dict["folder_id"] as? String {
                        onSelectFolder(folderId)
                    }
                } else {
                    // 变更操作，刷新目录树
                    await viewModel.loadTree()
                }
            }
        } catch {
            resultMessage = error.localizedDescription
            resultSuccess = false
        }
    }
}
