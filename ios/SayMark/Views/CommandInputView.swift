import SwiftUI

struct CommandInputView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var inputText = ""
    @State private var resultMessage: String?
    @State private var isSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.blue)

                    Spacer()

                    Text("语音输入")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)

                    Spacer()

                    Color.clear.frame(width: 44)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                VStack(spacing: 14) {
                    // 文字输入区域 + 麦克风
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading) {
                            if inputText.isEmpty {
                                Text("明天下午3点面试，地点在字节跳动上海办公室...")
                                    .foregroundColor(UIConstants.label3)
                            }
                            TextEditor(text: $inputText)
                                .font(.system(size: 16))
                                .foregroundColor(UIConstants.label)
                                .lineSpacing(4)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                        }
                        .padding(12)
                        .background(UIConstants.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(UIConstants.separator, lineWidth: 1)
                        )

                        // 麦克风按钮
                        Button {
                            if speechRecognizer.isRecording {
                                speechRecognizer.stopRecording()
                                if !speechRecognizer.transcript.isEmpty {
                                    inputText = speechRecognizer.transcript
                                }
                            } else {
                                Task { await speechRecognizer.startRecording() }
                            }
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(speechRecognizer.isRecording ? UIConstants.red : UIConstants.blue))
                                .shadow(color: UIConstants.blue.opacity(0.33), radius: 14, y: 4)
                        }
                    }

                    // 语音转录文本
                    if speechRecognizer.isRecording {
                        Text(speechRecognizer.transcript.isEmpty ? "正在聆听..." : speechRecognizer.transcript)
                            .font(.system(size: 14))
                            .foregroundColor(UIConstants.label3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(UIConstants.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 提示文字
                    HStack {
                        Text("例：明天下午3点面试 / 定位到工作文件夹 / 把这条笔记移到个人")
                            .font(.system(size: 13))
                            .foregroundColor(UIConstants.label3)
                            .lineSpacing(2)
                        Spacer()
                    }
                    .padding(10)
                    .background(UIConstants.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 发送按钮
                    Button {
                        sendCommand()
                    } label: {
                        Text("发送")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? UIConstants.blue.opacity(0.4)
                                : UIConstants.blue
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: UIConstants.blue.opacity(0.27), radius: 16, y: 4)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)

                    // 结果卡片
                    if let msg = resultMessage {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isSuccess ? UIConstants.green : UIConstants.red)
                                        .frame(width: 24, height: 24)
                                    Image(systemName: isSuccess ? "checkmark" : "xmark")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                Text(isSuccess ? "成功" : "失败")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isSuccess ? UIConstants.green : UIConstants.red)
                            }

                            Text(msg)
                                .font(.system(size: 14))
                                .foregroundColor(isSuccess ? UIConstants.label : UIConstants.label3)
                                .lineSpacing(2)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            (isSuccess ? UIConstants.green : UIConstants.red).opacity(0.08)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke((isSuccess ? UIConstants.green : UIConstants.red).opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)

                Spacer()
            }
            .background(UIConstants.background)
        }
    }

    private func sendCommand() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        Task {
            do {
                let result = try await APIClient.shared.sendCommand(text: text)
                isSuccess = result.success
                resultMessage = result.message
                if result.success {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                }
            } catch {
                isSuccess = false
                resultMessage = error.localizedDescription
            }
        }
    }
}
