import SwiftUI

struct FileDetailView: View {
    let fileId: String
    let fileName: String

    @StateObject private var viewModel = NoteViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedContent = ""
    @State private var savedTitle = ""
    @State private var savedContent = ""
    @State private var cursorOffset: Int? = nil
    @State private var showSaveToast = false
    @State private var showUnsavedAlert = false
    @State private var isVoiceEditing = false
    @State private var voiceEditText = ""
    @State private var showRenameSheet = false
    @State private var showMoveSheet = false

    /// 是否有未保存的更改
    private var hasUnsavedChanges: Bool {
        isEditing && (editedTitle != savedTitle || editedContent != savedContent)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Button {
                        handleBack()
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

                    Menu {
                        Button {
                            showRenameSheet = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button {
                            showMoveSheet = true
                        } label: {
                            Label("将文件移动到...", systemImage: "folder")
                        }
                        Menu {
                            Button {
                                exportPDF()
                            } label: {
                                Label("PDF", systemImage: "doc.richtext")
                            }
                            Button {
                                exportMarkdown()
                            } label: {
                                Label("Markdown", systemImage: "doc.plaintext")
                            }
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                            .frame(width: 32, height: 32)
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

            // 已保存提示
            if showSaveToast {
                saveToast
                    .transition(.opacity)
            }
        }
        .background(isEditing ? UIConstants.background : Color.white)
        .navigationBarHidden(true)
        .background(InteractivePopGestureDisabler(isDisabled: hasUnsavedChanges))
        .alert("内容已更改", isPresented: $showUnsavedAlert) {
            Button("保存", role: .none) {
                saveEdit(shouldDismiss: true)
            }
            Button("不保存", role: .destructive) {
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("内容已更改，是否保存？")
        }
        .task {
            viewModel.fileId = fileId
            await viewModel.reload()
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(
                title: "重命名文件",
                currentName: viewModel.note?.name ?? ""
            ) { newName in
                Task { await viewModel.save(name: newName, content: viewModel.note?.content ?? "") }
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            FolderMoveSheet(viewModel: viewModel)
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
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        enterEditMode(cursorOffset: estimateCursorOffset(at: value.location))
                    }
            )
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
            CustomTextEditor(text: $editedContent, cursorOffset: $cursorOffset)
                .font(.system(size: 14, design: .monospaced))
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
                    editedContent = savedContent
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22))
                    .foregroundColor(isEditing ? UIConstants.label3 : UIConstants.label3.opacity(0.45))
            }
            .frame(maxWidth: .infinity)

            // 语音麦克风
            Button {
                startVoiceEdit()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(UIConstants.blue))
                    .shadow(color: UIConstants.blue.opacity(0.38), radius: 10, y: 2)
            }
            .frame(maxWidth: .infinity)

            // 保存（编辑时显示） / 占位（保持居中）
            if isEditing {
                Button {
                    saveEdit()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(UIConstants.blue)
                }
                .frame(maxWidth: .infinity)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 44)
            }
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

    // MARK: - Save Toast
    private var saveToast: some View {
        VStack {
            Spacer()
            Text("已保存")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
                .padding(.bottom, 80)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions
    private func enterEditMode(cursorOffset: Int? = nil) {
        editedTitle = viewModel.note?.name ?? ""
        editedContent = viewModel.note?.content ?? ""
        savedTitle = viewModel.note?.name ?? ""
        savedContent = viewModel.note?.content ?? ""
        self.cursorOffset = cursorOffset
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func saveEdit(shouldDismiss: Bool = false) {
        Task {
            await viewModel.save(name: editedTitle, content: editedContent)
            await MainActor.run {
                savedTitle = editedTitle
                savedContent = editedContent
                isEditing = false
                if shouldDismiss {
                    dismiss()
                } else {
                    showSaveToast = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { showSaveToast = false }
                    }
                }
            }
        }
    }

    private func handleBack() {
        if hasUnsavedChanges {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    /// 根据点击位置估算光标在原文中的字符偏移（行高近似映射）
    private func estimateCursorOffset(at location: CGPoint) -> Int {
        let content = viewModel.note?.content ?? ""
        guard !content.isEmpty else { return 0 }
        let lineHeight: CGFloat = 22
        // 标题区约 50pt（标题字号 26 + 底部间距 12 + 顶部 padding）
        let contentTopY: CGFloat = 50
        let y = max(0, location.y - contentTopY)
        let lineIndex = Int(y / lineHeight)
        return characterOffset(forLine: lineIndex, in: content)
    }

    private func characterOffset(forLine line: Int, in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        let clamped = min(max(line, 0), lines.count)
        for i in 0..<clamped {
            offset += lines[i].count + 1  // +1 for newline
        }
        return offset
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

    // MARK: - Export
    private func exportMarkdown() {
        guard let note = viewModel.note else { return }
        let content = note.content ?? ""
        let fullMD = "# \(note.name)\n\n\(content)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(note.name).md")
        try? fullMD.write(to: tempURL, atomically: true, encoding: .utf8)
        presentShareSheet(with: tempURL)
    }

    private func exportPDF() {
        guard let note = viewModel.note else { return }
        let content = note.content ?? ""
        let html = markdownToHTML(title: note.name, content: content)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(note.name).pdf")
        renderPDF(from: html, to: tempURL)
        presentShareSheet(with: tempURL)
    }

    private func markdownToHTML(title: String, content: String) -> String {
        // 简单的 Markdown → HTML，处理基础语法
        var html = content
        // Headings
        html = html.replacingOccurrences(of: "### ", with: "<h3>")
        // Handle closing of headings
        html = replaceHeadings(in: html)
        // Bold
        html = html.replacingOccurrences(of: "**", with: "<b>")
        html = html.replacingOccurrences(of: "__", with: "<b>")
        // Replace alternating <b> with </b> (simplistic)
        html = balanceTags(in: html, tag: "b")
        // Italic
        html = html.replacingOccurrences(of: "*", with: "<i>")
        html = html.replacingOccurrences(of: "_", with: "<i>")
        html = balanceTags(in: html, tag: "i")
        // Newlines to <br/>
        html = html.replacingOccurrences(of: "\n", with: "<br/>")
        // List items
        html = html.replacingOccurrences(of: "- ", with: "&bull; ")

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><style>
        body { font-family: -apple-system, 'PingFang SC', sans-serif; padding: 20px 24px; font-size: 14pt; line-height: 1.7; color: #1c1c1e; }
        h1 { font-size: 22pt; font-weight: bold; margin-bottom: 12px; }
        h2 { font-size: 17pt; font-weight: bold; margin-top: 16px; margin-bottom: 6px; }
        h3 { font-size: 14pt; font-weight: bold; margin-top: 12px; margin-bottom: 4px; }
        </style></head>
        <body><h1>\(title)</h1>\(html)</body>
        </html>
        """
    }

    private func replaceHeadings(in text: String) -> String {
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i...].hasPrefix("<h3>") {
                let rest = text[text.index(i, offsetBy: 4)...]
                if let br = rest.firstIndex(of: "<") {
                    let headingText = String(rest[..<br])
                    result += "<h3>\(headingText)</h3>"
                    i = br
                } else {
                    result += "<h3>\(rest)</h3>"
                    break
                }
            } else if text[i...].hasPrefix("<h2>") {
                let rest = text[text.index(i, offsetBy: 4)...]
                if let br = rest.firstIndex(of: "<") {
                    let headingText = String(rest[..<br])
                    result += "<h2>\(headingText)</h2>"
                    i = br
                } else {
                    result += "<h2>\(rest)</h2>"
                    break
                }
            } else if text[i...].hasPrefix("<h1>") {
                let rest = text[text.index(i, offsetBy: 4)...]
                if let br = rest.firstIndex(of: "<") {
                    let headingText = String(rest[..<br])
                    result += "<h1>\(headingText)</h1>"
                    i = br
                } else {
                    result += "<h1>\(rest)</h1>"
                    break
                }
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        return result
    }

    private func balanceTags(in text: String, tag: String) -> String {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var result = ""
        var isOpen = false
        var i = text.startIndex
        while i < text.endIndex {
            if text[i...].hasPrefix(open) {
                result += isOpen ? close + open : open
                isOpen.toggle()
                i = text.index(i, offsetBy: open.count)
            } else if text[i...].hasPrefix(close) {
                result.append(close)
                isOpen = false
                i = text.index(i, offsetBy: close.count)
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }
        if isOpen { result += close }
        return result
    }

    private func renderPDF(from html: String, to url: URL) {
        let renderer = UIPrintPageRenderer()
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.contentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        renderer.setValue(pageRect, forKey: "paperRect")
        renderer.setValue(pageRect, forKey: "printableRect")

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: pageRect)
        }
        UIGraphicsEndPDFContext()
        try? pdfData.write(to: url)
    }

    private func presentShareSheet(with url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented VC
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Custom Text Editor (支持光标定位)
struct CustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = UIColor.label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        if let offset = cursorOffset {
            let length = (text as NSString).length
            let location = min(max(offset, 0), length)
            textView.selectedRange = NSRange(location: location, length: 0)
            textView.becomeFirstResponder()
            DispatchQueue.main.async {
                cursorOffset = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextEditor

        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

// MARK: - Disable interactive pop gesture (避免左滑绕过未保存提示)
struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        DispatchQueue.main.async {
            vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
        }
    }
}

// MARK: - Folder Move Sheet
struct FolderMoveSheet: View {
    @ObservedObject var viewModel: NoteViewModel
    @StateObject private var treeVM = FolderTreeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderId: String? = nil

    var body: some View {
        NavigationStack {
            List {
                // 顶级目录 (移动到根目录)
                Button {
                    selectedFolderId = ""
                } label: {
                    HStack(spacing: 12) {
                        RowIcon(systemName: "folder.fill", color: UIConstants.label3)
                        Text("根目录（顶级）")
                            .font(.system(size: 17))
                            .foregroundColor(UIConstants.label)
                            .kerning(-0.41)
                        Spacer()
                        if selectedFolderId == "" {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(UIConstants.blue)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 所有文件夹
                ForEach(allFolders(), id: \.id) { folder in
                    Button {
                        selectedFolderId = folder.id
                    } label: {
                        HStack(spacing: 12) {
                            RowIcon(systemName: "folder.fill", color: UIConstants.blue)
                            Text(folder.name)
                                .font(.system(size: 17))
                                .foregroundColor(UIConstants.label)
                                .kerning(-0.41)
                            Spacer()
                            if selectedFolderId == folder.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(UIConstants.blue)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("移动到...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(UIConstants.blue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("移动") {
                        guard let targetId = selectedFolderId,
                              let fileId = viewModel.note?.id else { return }
                        Task {
                            try? await APIClient.shared.moveFile(id: fileId, targetFolderId: targetId)
                            await MainActor.run { dismiss() }
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(selectedFolderId != nil ? UIConstants.blue : UIConstants.blue.opacity(0.35))
                    .disabled(selectedFolderId == nil)
                }
            }
        }
        .task {
            await treeVM.loadTree()
        }
    }

    /// 递归收集所有文件夹（扁平化）
    private func allFolders() -> [FlatFolder] {
        var result: [FlatFolder] = []
        func collect(_ nodes: [TreeNode], depth: Int) {
            for node in nodes {
                result.append(FlatFolder(id: node.id, name: node.name, depth: depth))
                collect(node.children, depth: depth + 1)
            }
        }
        collect(treeVM.tree, depth: 0)
        return result
    }
}

private struct FlatFolder {
    let id: String
    let name: String
    let depth: Int
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
