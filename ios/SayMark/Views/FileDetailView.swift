import SwiftUI

struct FileDetailView: View {
    @StateObject private var noteVM: NoteViewModel
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editContent = ""

    // 语音编辑
    @State private var showVoiceEdit = false
    @State private var voiceInputText = ""
    @State private var isSending = false
    @StateObject private var recognizer = SpeechRecognizer()

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
                    Text((noteVM.note.content ?? "").isEmpty ? "(无内容)" : (noteVM.note.content ?? ""))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }

            // 底部工具栏
            if !isEditing {
                HStack(spacing: 24) {
                    // 话筒按钮
                    Button {
                        voiceInputText = ""
                        showVoiceEdit = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(Color.accentColor))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(noteVM.note.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    // 撤回按钮
                    if !isEditing && !contentHistory.isEmpty {
                        Button {
                            undoLastChange()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                    Button(isEditing ? "保存" : "编辑") {
                        if isEditing {
                            Task {
                                await noteVM.save(name: editName, content: editContent)
                                await viewModel.loadTree()
                                isEditing = false
                            }
                        } else {
                            editName = noteVM.note.name
                            editContent = noteVM.note.content ?? ""
                            isEditing = true
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
        // 语音编辑 sheet
        .sheet(isPresented: $showVoiceEdit) {
            voiceEditSheet
        }
    }

    // MARK: - 语音编辑 Sheet

    private var voiceEditSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    TextField("例如：把时间改成下午3点 / 加上记得带身份证", text: $voiceInputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        Task {
                            if recognizer.isRecording {
                                recognizer.stopRecording()
                                if !recognizer.transcript.isEmpty {
                                    voiceInputText = recognizer.transcript
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
                    Task { await sendVoiceEdit() }
                } label: {
                    Text(isSending ? "调整中..." : "调整笔记")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(voiceInputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("语音调整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        recognizer.stopRecording()
                        showVoiceEdit = false
                    }
                }
            }
            .onDisappear { recognizer.stopRecording() }
            .alert("识别错误", isPresented: Binding(
                get: { recognizer.errorMessage != nil },
                set: { if !$0 { recognizer.errorMessage = nil } }
            )) {
                Button("好") { recognizer.errorMessage = nil }
            } message: {
                Text(recognizer.errorMessage ?? "")
            }
        }
    }

    // MARK: - 发送语音编辑指令

    private func sendVoiceEdit() async {
        let text = voiceInputText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                showVoiceEdit = false
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
