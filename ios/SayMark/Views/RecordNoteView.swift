import SwiftUI

struct RecordNoteView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let targetFolderId: String?
    @StateObject private var recognizer = SpeechRecognizer()
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("目标文件夹：\(folderName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        if recognizer.isRecording {
                            recognizer.stopRecording()
                            await saveNote()
                        } else {
                            await recognizer.startRecording()
                        }
                    }
                } label: {
                    Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundStyle(recognizer.isRecording ? .red : .tint)
                }
                .disabled(isSaving)

                Text(isSaving ? "正在保存..." : (recognizer.isRecording ? "正在识别，点击停止" : "点击按钮开始录音"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(recognizer.transcript.isEmpty ? "识别文字将显示在这里" : recognizer.transcript)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("录音笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { recognizer.stopRecording(); dismiss() }
                }
            }
            .onDisappear { recognizer.stopRecording() }
            .alert("出错了", isPresented: Binding(
                get: { error != nil || recognizer.errorMessage != nil },
                set: { newVal in
                    if !newVal { error = nil; recognizer.errorMessage = nil }
                }
            )) {
                Button("好") { error = nil; recognizer.errorMessage = nil }
            } message: {
                Text(error ?? recognizer.errorMessage ?? "")
            }
        }
    }

    private var folderName: String {
        guard let targetFolderId = targetFolderId else { return "未分类" }
        return findFolderName(in: viewModel.tree, id: targetFolderId) ?? "未分类"
    }

    private func findFolderName(in nodes: [TreeNode], id: String) -> String? {
        for node in nodes {
            if node.folder.id == id { return node.folder.name }
            if let name = findFolderName(in: node.children, id: id) {
                return name
            }
        }
        return nil
    }

    private func saveNote() async {
        let transcript = recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            error = "没有识别到文字"
            return
        }
        isSaving = true
        do {
            _ = try await APIClient.shared.createNote(transcript: transcript, targetFolderId: targetFolderId)
            await viewModel.loadTree()
            isSaving = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}
