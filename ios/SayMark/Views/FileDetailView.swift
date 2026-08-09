import SwiftUI

/// Figma 风格的笔记详情视图
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
            ScrollView {
                if isEditing {
                    editModeContent
                } else {
                    previewModeContent
                }
            }
            .overlay {
                if isSending {
                    loadingOverlay
                }
            }

            // 底部工具栏
            bottomToolbar
        }
        .navigationTitle(isEditing ? "编辑" : "")
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
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignColor.blue)
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
        .task { await noteVM.reload() }
        .onAppear { viewModel.hideFloatingButton = true }
        .onDisappear { viewModel.hideFloatingButton = false }
    }

    // MARK: - 预览模式

    private var previewModeContent: some View {
        Group {
            if let content = noteVM.note.content, !content.isEmpty {
                MarkdownPreview(content: content)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            } else {
                Text("(无内容)")
                    .foregroundStyle(DesignColor.label3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    // MARK: - 编辑模式（Figma 风格）

    private var editModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题输入
            TextField("标题", text: $editName)
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DesignColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignColor.separatorLight, lineWidth: 1)
                )

            // 内容输入
            TextEditor(text: $editContent)
                .font(.system(size: 14))
                .frame(minHeight: 320)
                .padding(8)
                .background(DesignColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignColor.separatorLight, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - 底部工具栏

    private var bottomToolbar: some View {
        HStack(spacing: 32) {
            // 撤回
            if !contentHistory.isEmpty {
                Button {
                    undoLastChange()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignColor.blue)
                }
            } else {
                Spacer().frame(width: 20)
            }

            Spacer()

            // 话筒按钮
            Button {
                // 语音编辑
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignColor.blue)
                        .frame(width: 46, height: 46)
                        .shadow(color: DesignColor.blue.opacity(0.4), radius: 10, y: 2)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            // 编辑
            if !isEditing {
                Button {
                    editName = noteVM.note.name
                    editContent = noteVM.note.content ?? ""
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignColor.blue)
                }
            } else {
                Spacer().frame(width: 20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 加载状态

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(DesignColor.blue)
            Text("正在调整笔记...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DesignColor.label3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignColor.card.opacity(0.7))
    }

    // MARK: - 语音编辑

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
                contentHistory.append(oldContent)
                await noteVM.reload()
                await viewModel.loadTree()
            }
        } catch {}
    }

    private func undoLastChange() {
        guard let previousContent = contentHistory.popLast() else { return }
        Task {
            await noteVM.save(name: noteVM.note.name, content: previousContent)
            await noteVM.reload()
            await viewModel.loadTree()
        }
    }
}

// MARK: - Markdown 预览

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
            Color.clear.frame(height: 6)
        } else if trimmed.hasPrefix("### ") {
            Text(inlineFormatted(String(trimmed.dropFirst(4))))
                .font(.headline)
        } else if trimmed.hasPrefix("## ") {
            Text(inlineFormatted(String(trimmed.dropFirst(3))))
                .font(.title3)
                .fontWeight(.bold)
        } else if trimmed.hasPrefix("# ") {
            Text(inlineFormatted(String(trimmed.dropFirst(2))))
                .font(.title)
                .fontWeight(.bold)
        } else if trimmed.hasPrefix("> ") {
            Text(inlineFormatted(String(trimmed.dropFirst(2))))
                .italic()
                .foregroundStyle(DesignColor.label3)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DesignColor.separator)
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
            Color.clear.frame(height: 0)
        } else {
            Text(inlineFormatted(trimmed))
        }
    }

    private func inlineFormatted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for match in text.matches(of: #/\*\*(.+?)\*\*/#) {
            let full = String(match.0)
            let inner = String(match.1)
            if let range = result.range(of: full) {
                var replacement = AttributedString(inner)
                replacement.font = Font.body.bold()
                result.replaceSubrange(range, with: replacement)
            }
        }
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
