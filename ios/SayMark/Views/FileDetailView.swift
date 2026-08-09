import SwiftUI

struct FileDetailView: View {
    let fileId: String
    let fileName: String

    @StateObject private var viewModel = NoteViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedContent = ""
    @State private var previousContent = ""
    @State private var isVoiceEditing = false
    @State private var voiceEditText = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(UIConstants.blue)
                            Text("文件")
                                .font(.system(size: 17))
                                .foregroundColor(UIConstants.blue)
                        }
                    }

                    Spacer()

                    Text(isEditing ? "编辑" : viewModel.note?.name ?? fileName)
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                        .lineLimit(1)

                    Spacer()

                    if isEditing {
                        Button("保存") {
                            saveEdit()
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(UIConstants.blue)
                    } else {
                        Button {
                            enterEditMode()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 18))
                                .foregroundColor(UIConstants.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    (isEditing ? UIConstants.background : Color.white).opacity(0.9)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                // 内容区
                if viewModel.loading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let note = viewModel.note {
                    if isEditing {
                        editModeView
                    } else {
                        viewModeView(note: note)
                    }
                } else {
                    Spacer()
                }

                // 底部工具栏
                bottomToolbar
            }

            // 语音编辑加载浮层
            if isVoiceEditing {
                voiceEditOverlay
            }
        }
        .background(isEditing ? UIConstants.background : Color.white)
        .navigationBarHidden(true)
        .task {
            viewModel.fileId = fileId
            await viewModel.reload()
        }
    }

    // MARK: - View Mode
    private func viewModeView(note: NoteFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 大标题
                Text(note.name)
                    .font(.system(size: 26, weight: .bold))
                    .kerning(0.3)
                    .foregroundColor(UIConstants.label)
                    .padding(.bottom, 12)

                if let content = note.content, !content.isEmpty {
                    MarkdownPreview(text: content)
                } else {
                    Text("暂无内容")
                        .font(.system(size: 16))
                        .foregroundColor(UIConstants.label3)
                        .padding(.top, 8)
                }

                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(Color.white)
    }

    // MARK: - Edit Mode
    private var editModeView: some View {
        VStack(spacing: 12) {
            // 标题
            TextField("标题", text: $editedTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(UIConstants.label)
                .padding(10)
                .background(UIConstants.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(UIConstants.separator, lineWidth: 1)
                )

            // 内容
            TextEditor(text: $editedContent)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(UIConstants.label)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxHeight: .infinity)
                .background(UIConstants.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(UIConstants.separator, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Bottom Toolbar
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // 撤销
            Button {
                if isEditing {
                    editedContent = previousContent
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22))
                    .foregroundColor(UIConstants.label3.opacity(0.45))
            }
            .frame(maxWidth: .infinity)

            // 语音麦克风
            Button {
                startVoiceEdit()
            } label: {
                TabIcon(type: "mic", size: 22, color: .white, strokeWidth: 2)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(UIConstants.blue))
                    .shadow(color: UIConstants.blue.opacity(0.38), radius: 10, y: 2)
            }
            .frame(maxWidth: .infinity)

            // 编辑/查看切换
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isEditing {
                        saveEdit()
                    } else {
                        enterEditMode()
                    }
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 22))
                    .foregroundColor(UIConstants.blue)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 54)
        .background(
            (isEditing ? UIConstants.background : Color(red: 0.949, green: 0.949, blue: 0.969, opacity: 0.95))
                .background(Material.ultraThin)
        )
        .overlay(alignment: .top) {
            HDSeparator()
        }
    }

    // MARK: - Voice Edit Overlay
    private var voiceEditOverlay: some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(UIConstants.blue)

                Text("正在调整笔记...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(UIConstants.label3)
            }
        }
    }

    // MARK: - Actions
    private func enterEditMode() {
        editedTitle = viewModel.note?.name ?? ""
        editedContent = viewModel.note?.content ?? ""
        previousContent = viewModel.note?.content ?? ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func saveEdit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        Task {
            await viewModel.save(name: editedTitle, content: editedContent)
        }
    }

    private func startVoiceEdit() {
        isVoiceEditing = true
        // 模拟语音处理延迟
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                isVoiceEditing = false
            }
            // 实际应调用 API: sendVoiceEdit
            if !isEditing {
                enterEditMode()
            }
        }
    }
}

// MARK: - Markdown Preview
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let content, let level):
                    Text(content)
                        .font(.system(
                            size: level == 1 ? 20 : level == 2 ? 17 : 15,
                            weight: .bold
                        ))
                        .foregroundColor(UIConstants.label)
                        .padding(.top, level == 1 ? 12 : 8)
                        .padding(.bottom, 4)

                case .body(let content):
                    Text(content)
                        .font(.system(size: 16))
                        .foregroundColor(UIConstants.label)
                        .lineSpacing(4)
                        .kerning(-0.32)
                        .padding(.vertical, 3)

                case .blockquote(let content):
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(UIConstants.label3.opacity(0.25))
                            .frame(width: 3)
                            .padding(.trailing, 12)
                        Text(content)
                            .font(.system(size: 15))
                            .italic()
                            .foregroundColor(UIConstants.label3)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 6)

                case .bulletItem(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(UIConstants.label)
                        Text(content)
                            .font(.system(size: 15))
                            .foregroundColor(UIConstants.label)
                            .lineSpacing(3)
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 1.5)

                case .orderedItem(let index, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index).")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(UIConstants.label)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(content)
                            .font(.system(size: 15))
                            .foregroundColor(UIConstants.label)
                            .lineSpacing(3)
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 1.5)
                }
            }
        }
    }

    private enum BlockType {
        case heading(String, Int)
        case body(String)
        case blockquote(String)
        case bulletItem(String)
        case orderedItem(Int, String)
    }

    private func parseBlocks() -> [BlockType] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [BlockType] = []
        var orderedCounter = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Heading
            if trimmed.hasPrefix("### ") {
                orderedCounter = 0
                blocks.append(.heading(String(trimmed.dropFirst(4)), 3))
            } else if trimmed.hasPrefix("## ") {
                orderedCounter = 0
                blocks.append(.heading(String(trimmed.dropFirst(3)), 2))
            } else if trimmed.hasPrefix("# ") {
                orderedCounter = 0
                blocks.append(.heading(String(trimmed.dropFirst(2)), 1))
            }
            // Blockquote
            else if trimmed.hasPrefix("> ") {
                orderedCounter = 0
                blocks.append(.blockquote(String(trimmed.dropFirst(2))))
            }
            // Unordered list
            else if trimmed.hasPrefix("- ") {
                orderedCounter = 0
                blocks.append(.bulletItem(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") {
                orderedCounter = 0
                blocks.append(.bulletItem(String(trimmed.dropFirst(2))))
            }
            // Ordered list
            else if let match = trimmed.range(of: #"^\d+\."#, options: .regularExpression) {
                orderedCounter += 1
                let contentStart = trimmed.index(match.upperBound, offsetBy: trimmed[match.upperBound...].hasPrefix(" ") ? 1 : 0)
                blocks.append(.orderedItem(orderedCounter, String(trimmed[contentStart...])))
            }
            // Normal text
            else {
                orderedCounter = 0
                blocks.append(.body(trimmed))
            }
        }

        return blocks
    }
}
