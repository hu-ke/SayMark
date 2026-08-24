import SwiftUI
import UIKit
import PhotosUI

struct FileDetailView: View {
    let fileId: String
    let fileName: String

    @StateObject private var viewModel = NoteViewModel()
    @ObservedObject var folderTreeViewModel: FolderTreeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedContent = ""
    @State private var previousContent = ""
    @State private var isVoiceEditing = false
    @StateObject private var voice = VoiceRecorder()
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showMoveSheet = false
    @State private var exportItem: ExportItem?
    @State private var showToast = false
    @State private var toastText = "已保存"
    @State private var activeDialog: Dialog?

    // 编辑工具
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadedImageURLs: [String] = []
    @State private var isUploadingImage = false

    private enum Dialog: String, Identifiable {
        case delete, unsaved
        var id: String { rawValue }
    }

    private enum Field { case title, content }
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Button {
                        attemptDismiss()
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
                        Color.clear.frame(width: 44, height: 44)
                    } else {
                        Menu {
                            Button {
                                renameText = viewModel.note?.name ?? fileName
                                showRenameAlert = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button {
                                showMoveSheet = true
                            } label: {
                                Label("将文件移动到...", systemImage: "folder")
                            }
                            Button {
                                export(type: .pdf)
                            } label: {
                                Label("导出 PDF", systemImage: "doc.richtext")
                            }
                            Button {
                                export(type: .md)
                            } label: {
                                Label("导出 Markdown", systemImage: "doc.plaintext")
                            }
                            Button(role: .destructive) {
                                activeDialog = .delete
                            } label: {
                                Label("删除文件", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(UIConstants.blue)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.9)
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

            // 提示 Toast
            if showToast {
                VStack {
                    Spacer()
                    Text(toastText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 130)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(120)
            }
        }
        .background(UIConstants.background)
        .navigationBarHidden(true)
        .voiceRecorderOverlay(voice)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let w = value.translation.width
                    let h = value.translation.height
                    // 从左侧边缘右滑，等同于点击返回（编辑中会触发未保存提示）
                    if value.startLocation.x < 40, w > 80, abs(w) > abs(h) {
                        attemptDismiss()
                    }
                }
        )
        .task {
            viewModel.fileId = fileId
            await viewModel.reload()
        }
        .onAppear {
            folderTreeViewModel.hideFloatingButton = true
            // 识别结果路由：松开发送/转文字确认 → 调整当前笔记
            voice.onResult = { result in
                if case .send(let text) = result {
                    Task { await adjustNote(with: text) }
                }
            }
        }
        .onDisappear {
            folderTreeViewModel.hideFloatingButton = false
            // 返回列表页时刷新目录树，保证详情页内的重命名/编辑/删除等改动即时可见
            Task { await folderTreeViewModel.loadTree() }
        }
        .alert("重命名文件", isPresented: $showRenameAlert) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                Task { await viewModel.save(name: trimmed, content: viewModel.note?.content ?? "") }
            }
        }
        .confirmationDialog(
            activeDialog == .delete ? "删除文件" : "内容已更改",
            isPresented: Binding(
                get: { activeDialog != nil },
                set: { if !$0 { activeDialog = nil } }
            ),
            titleVisibility: .visible,
            presenting: activeDialog
        ) { dialog in
            switch dialog {
            case .delete:
                Button("删除", role: .destructive) { deleteFile() }
                Button("取消", role: .cancel) {}
            case .unsaved:
                Button("保存") { saveAndDismiss() }
                Button("不保存", role: .destructive) {
                    isEditing = false
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        } message: { dialog in
            switch dialog {
            case .delete:
                Text("将删除「\(viewModel.note?.name ?? fileName)」。此操作不可撤销。")
            case .unsaved:
                Text("是否保存当前更改？")
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            FolderMoveSheet(folders: flattenFolders(folderTreeViewModel.tree)) { folderId in
                moveTo(folderId)
            }
        }
        .sheet(item: $exportItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhoto(newItem) }
        }
    }

    // MARK: - View Mode
    private func viewModeView(note: NoteFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 大标题
                Text(note.name)
                    .font(.system(size: 28, weight: .bold))
                    .kerning(0.3)
                    .foregroundColor(UIConstants.label)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEditMode(focus: .title) }

                // 安排/闹钟信息卡片
                if note.isAppointment || note.isAlarm {
                    ScheduleInfoCard(note: note)
                }

                // 正文
                if let content = note.content, !content.isEmpty {
                    MarkdownPreview(text: content)
                        .contentShape(Rectangle())
                        .onTapGesture { enterEditMode(focus: .content) }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 34))
                            .foregroundColor(UIConstants.label3.opacity(0.5))
                        Text("暂无内容")
                            .font(.system(size: 16))
                            .foregroundColor(UIConstants.label3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEditMode(focus: .content) }
                }

                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Edit Mode
    private var editModeView: some View {
        VStack(spacing: 12) {
            // 标题
            TextField("标题", text: $editedTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(UIConstants.label)
                .focused($focusedField, equals: .title)
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
                .focused($focusedField, equals: .content)
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

            // 已上传图片缩略图
            if !uploadedImageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(uploadedImageURLs, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    Color(UIConstants.fill)
                                } else {
                                    Color(UIConstants.fill).overlay(ProgressView().scaleEffect(0.7))
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Bottom Toolbar
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // 编辑工具条（图片 / 列表 / 加粗 / 斜体 / 标题 / 引用）
            if isEditing {
                editToolStrip
                HDSeparator()
            }

            HStack(spacing: 0) {
                // 撤销
                Button {
                    if isEditing {
                        editedContent = previousContent
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 22))
                        .foregroundColor(canUndo ? UIConstants.blue : UIConstants.label3.opacity(0.45))
                }
                .frame(maxWidth: .infinity)

                // 语音麦克风（按住说话，松开后由 AI 调整当前笔记）
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(voice.isRecording ? UIConstants.red : UIConstants.blue))
                    .shadow(color: (voice.isRecording ? UIConstants.red : UIConstants.blue).opacity(0.38), radius: 10, y: 2)
                    .contentShape(Circle())
                    .voiceRecordGesture(recorder: voice)
                    .frame(maxWidth: .infinity)

                // 右下角：编辑时显示保存，非编辑时留空
                if isEditing {
                    Button {
                        saveEdit()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(UIConstants.blue)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 54)
        }
        .background(
            Color(red: 0.949, green: 0.949, blue: 0.969, opacity: 0.95)
                .background(Material.ultraThin)
        )
        .overlay(alignment: .top) {
            HDSeparator()
        }
    }

    // MARK: - Edit Tool Strip
    private var editToolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    toolIcon("photo")
                }
                .disabled(isUploadingImage)

                Menu {
                    Button("1. 2. 3. 数字") { insertListMarker("1. ") }
                    Button("• 原点") { insertListMarker("- ") }
                    Button("♥ 爱心") { insertListMarker("♥ ") }
                    Button("★ 五角星") { insertListMarker("★ ") }
                } label: {
                    toolIcon("list.bullet")
                }

                Button { insertInline("**粗体**") } label: { toolIcon("bold") }
                Button { insertInline("*斜体*") } label: { toolIcon("italic") }
                Button { insertLinePrefix("## ") } label: { toolIcon("textformat") }
                Button { insertLinePrefix("> ") } label: { toolIcon("text.quote") }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func toolIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20))
            .foregroundColor(UIConstants.label2)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    /// 在文末直接追加一段文本（加粗/斜体等）
    private func insertInline(_ text: String) {
        editedContent += text
        focusedField = .content
    }

    /// 以新行前缀形式插入（标题 / 引用）
    private func insertLinePrefix(_ prefix: String) {
        ensureTrailingNewline()
        editedContent += prefix
        focusedField = .content
    }

    /// 插入列表标记
    private func insertListMarker(_ marker: String) {
        ensureTrailingNewline()
        editedContent += marker + " "
        focusedField = .content
    }

    private func ensureTrailingNewline() {
        if !editedContent.isEmpty && !editedContent.hasSuffix("\n") {
            editedContent += "\n"
        }
    }

    // MARK: - Image Upload
    @MainActor
    private func handlePhoto(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        defer { isUploadingImage = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let jpeg = uiImage.jpegData(compressionQuality: 0.85) else {
                showToastMessage("无法读取图片")
                return
            }
            let url = try await APIClient.shared.uploadImage(imageData: jpeg)
            uploadedImageURLs.append(url)
            ensureTrailingNewline()
            editedContent += "![图片](\(url))"
            focusedField = .content
            showToastMessage("图片已上传")
        } catch {
            showToastMessage(error.localizedDescription)
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
    private var hasChanges: Bool {
        let savedTitle = viewModel.note?.name ?? ""
        let savedContent = viewModel.note?.content ?? ""
        return editedTitle.trimmingCharacters(in: .whitespaces) != savedTitle
            || editedContent != savedContent
    }

    /// 编辑中且正文已被改动时可撤销
    private var canUndo: Bool {
        isEditing && editedContent != previousContent
    }

    private func enterEditMode(focus: Field? = .content) {
        editedTitle = viewModel.note?.name ?? ""
        editedContent = viewModel.note?.content ?? ""
        previousContent = viewModel.note?.content ?? ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            focusedField = focus
        }
    }

    private func saveEdit() {
        let title = trimmedTitle()
        Task { @MainActor in
            await viewModel.save(name: title, content: editedContent)
            withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
            showToastMessage("已保存")
        }
    }

    private func saveAndDismiss() {
        let title = trimmedTitle()
        Task { @MainActor in
            await viewModel.save(name: title, content: editedContent)
            isEditing = false
            dismiss()
        }
    }

    private func attemptDismiss() {
        if isEditing && hasChanges {
            activeDialog = .unsaved
        } else {
            dismiss()
        }
    }

    private func trimmedTitle() -> String {
        let t = editedTitle.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (viewModel.note?.name ?? fileName) : t
    }

    @MainActor
    private func adjustNote(with prompt: String) async {
        isVoiceEditing = true
        do {
            let result = try await APIClient.shared.sendCommand(text: prompt, targetFileId: fileId)
            await viewModel.reload()
            await NotificationManager.shared.refreshFromServer()
            showToastMessage(result.message)
        } catch {
            showToastMessage(error.localizedDescription)
        }
        isVoiceEditing = false
    }

    private func showToastMessage(_ message: String) {
        toastText = message
        showToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            showToast = false
        }
    }

    // MARK: - Move
    private func moveTo(_ folderId: String) {
        guard folderId != viewModel.note?.parentId else { return }
        Task {
            await folderTreeViewModel.moveFile(id: fileId, targetFolderId: folderId)
        }
    }

    private func deleteFile() {
        Task { @MainActor in
            await folderTreeViewModel.deleteFile(id: fileId)
            dismiss()
        }
    }

    // MARK: - Export
    private enum ExportType {
        case pdf, md
    }

    private func export(type: ExportType) {
        guard let note = viewModel.note else { return }
        let title = note.name
        let content = note.content ?? ""
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        switch type {
        case .md:
            let md = "# \(title)\n\n\(content)"
            if let url = writeTemp(data: Data(md.utf8), filename: "\(safeTitle).md") {
                exportItem = ExportItem(url: url)
            }
        case .pdf:
            if let url = writeTemp(data: makePDF(title: title, content: content), filename: "\(safeTitle).pdf") {
                exportItem = ExportItem(url: url)
            }
        }
    }

    private func writeTemp(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func makePDF(title: String, content: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 尺寸
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
            ]
            (title as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttributes)

            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray,
            ]
            let bodyRect = CGRect(x: 40, y: 90, width: pageRect.width - 80, height: pageRect.height - 130)
            (content as NSString).draw(in: bodyRect, withAttributes: bodyAttributes)
        }
    }
}

// MARK: - Export & Move Helpers

struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FolderPickerItem: Identifiable {
    let id: String
    let name: String
    let depth: Int
}

func flattenFolders(_ nodes: [TreeNode], depth: Int = 0) -> [FolderPickerItem] {
    var result: [FolderPickerItem] = []
    for node in nodes {
        result.append(FolderPickerItem(id: node.id, name: node.name, depth: depth))
        result.append(contentsOf: flattenFolders(node.children, depth: depth + 1))
    }
    return result
}

struct FolderMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [FolderPickerItem]
    var onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .font(.system(size: 17))
                        .foregroundColor(UIConstants.blue)
                    Spacer()
                    Text("移动到")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                    Spacer()
                    Color.clear.frame(width: 60, height: 1)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) { HDSeparator() }

                List(folders) { item in
                    Button {
                        onSelect(item.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            RowIcon(iconType: "folder", color: UIConstants.blue)
                            Text(item.name)
                                .font(.system(size: 16))
                                .foregroundColor(UIConstants.label)
                            Spacer()
                        }
                        .padding(.leading, CGFloat(item.depth) * 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .background(UIConstants.background)
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
                    Text(inlineMarkdown(content))
                        .font(.system(
                            size: level == 1 ? 20 : level == 2 ? 17 : 15,
                            weight: .bold
                        ))
                        .foregroundColor(UIConstants.label)
                        .padding(.top, level == 1 ? 12 : 8)
                        .padding(.bottom, 4)

                case .body(let content):
                    Text(inlineMarkdown(content))
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
                        Text(inlineMarkdown(content))
                            .font(.system(size: 15))
                            .italic()
                            .foregroundColor(UIConstants.label3)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 6)

                case .image(let url):
                    AsyncImage(url: URL(string: url)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else if phase.error != nil {
                            Color(UIConstants.fill)
                        } else {
                            Color(UIConstants.fill).overlay(ProgressView())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.vertical, 6)

                case .bulletItem(let marker, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text(marker)
                            .foregroundColor(UIConstants.label)
                        Text(inlineMarkdown(content))
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
                        Text(inlineMarkdown(content))
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

    /// 行内 markdown（粗体/斜体/行内代码/链接）转为富文本
    private func inlineMarkdown(_ content: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(content)
    }

    private enum BlockType {
        case heading(String, Int)
        case body(String)
        case blockquote(String)
        case image(String)
        case bulletItem(marker: String, content: String)
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
            // Image（![alt](url)）
            else if trimmed.hasPrefix("![") {
                if let open = trimmed.range(of: "]("),
                   let close = trimmed[open.upperBound...].firstIndex(of: ")") {
                    let url = String(trimmed[open.upperBound..<close])
                    if url.hasPrefix("http") {
                        orderedCounter = 0
                        blocks.append(.image(url))
                    } else {
                        orderedCounter = 0
                        blocks.append(.body(trimmed))
                    }
                } else {
                    orderedCounter = 0
                    blocks.append(.body(trimmed))
                }
            }
            // Unordered list（支持原点 / 爱心 / 五角星等自定义标记）
            else if trimmed.hasPrefix("- ") {
                orderedCounter = 0
                blocks.append(.bulletItem(marker: "•", content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") {
                orderedCounter = 0
                blocks.append(.bulletItem(marker: "•", content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("♥ ") {
                orderedCounter = 0
                blocks.append(.bulletItem(marker: "♥", content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("★ ") {
                orderedCounter = 0
                blocks.append(.bulletItem(marker: "★", content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("• ") {
                orderedCounter = 0
                blocks.append(.bulletItem(marker: "•", content: String(trimmed.dropFirst(2))))
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

// MARK: - Schedule Info Card

struct ScheduleInfoCard: View {
    let note: NoteFile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: note.isAppointment ? "calendar" : "alarm")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(note.isAppointment ? UIConstants.orange : UIConstants.blue)
                Text(note.isAppointment ? "安排" : "闹钟")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(note.isAppointment ? UIConstants.orange : UIConstants.blue)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HDSeparator()

            if note.isAppointment {
                infoRow(icon: "calendar", title: "日期", value: note.date.isEmpty ? "—" : note.date)
                HDSeparator().padding(.leading, 14)
                infoRow(icon: "clock", title: "时间", value: note.timeDisplay.isEmpty ? "—" : note.timeDisplay)
            } else {
                infoRow(icon: "clock", title: "时间", value: note.timeDisplay)
                HDSeparator().padding(.leading, 14)
                infoRow(icon: "repeat", title: "周期", value: note.recurrenceLabel)
            }
        }
        .cardStyle()
        .padding(.bottom, 16)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(UIConstants.label3)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(UIConstants.label3)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(UIConstants.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
