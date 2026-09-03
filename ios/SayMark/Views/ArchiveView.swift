import SwiftUI

/// 归档列表：展示已归档笔记，支持恢复到原处或移动到其它路径
struct ArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var folderTreeViewModel = FolderTreeViewModel()

    @State private var files: [ArchivedFile] = []
    @State private var loading = false
    @State private var errorMessage: String?

    @State private var missingPathFile: ArchivedFile?   // 原路径不存在的文件，弹窗引导
    @State private var moveTarget: ArchivedFile?         // 需要选择目标文件夹的文件

    var body: some View {
        VStack(spacing: 0) {
            // 自定义导航栏
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                        Text("设置")
                            .font(.system(size: 17))
                            .foregroundColor(UIConstants.blue)
                    }
                }

                Spacer()

                Text("归档")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.41)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(
                UIConstants.background.opacity(0.82)
                    .background(Material.ultraThin)
            )
            .overlay(alignment: .bottom) { HDSeparator() }

            // 内容区
            if loading && files.isEmpty {
                Spacer()
                ProgressView().scaleEffect(1.2)
                Spacer()
            } else if files.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .background(UIConstants.background)
        .navigationBarHidden(true)
        .task {
            await load()
            await folderTreeViewModel.loadTree()
        }
        .alert(
            "原路径不存在",
            isPresented: Binding(
                get: { missingPathFile != nil },
                set: { if !$0 { missingPathFile = nil } }
            ),
            presenting: missingPathFile
        ) { file in
            Button("移动到其它路径") {
                moveTarget = file
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("原路径不存在，请选择其它路径")
        }
        .sheet(item: $moveTarget) { file in
            FolderMoveSheet(folders: flattenFolders(folderTreeViewModel.tree)) { folderId in
                Task { await move(file, to: folderId) }
            }
        }
    }

    // MARK: - 内容

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 42))
                .foregroundColor(UIConstants.label3.opacity(0.6))
            Text("暂无归档笔记")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(UIConstants.label3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var fileList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(files) { file in
                    ArchiveFileCard(
                        file: file,
                        onRestore: { Task { await restoreOriginal(file) } },
                        onMove: { moveTarget = file }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Color.clear.frame(height: 40)
        }
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            files = try await APIClient.shared.getArchivedFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func restoreOriginal(_ file: ArchivedFile) async {
        do {
            try await APIClient.shared.restoreFile(id: file.id, targetFolderId: nil)
            files.removeAll { $0.id == file.id }
        } catch {
            if error.localizedDescription.contains("原路径不存在") {
                missingPathFile = file
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func move(_ file: ArchivedFile, to folderId: String) async {
        do {
            try await APIClient.shared.restoreFile(id: file.id, targetFolderId: folderId)
            files.removeAll { $0.id == file.id }
            await folderTreeViewModel.loadTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 归档文件卡片

private struct ArchiveFileCard: View {
    let file: ArchivedFile
    let onRestore: () -> Void
    let onMove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: "doc.fill", color: UIConstants.label3)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                    .lineLimit(1)
                Text(file.archivedPath.isEmpty ? "原路径未知" : file.archivedPath)
                    .font(.system(size: 13))
                    .foregroundColor(UIConstants.label3)
                    .kerning(-0.08)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(action: onRestore) {
                    Label("恢复到原处", systemImage: "arrow.uturn.backward")
                }
                Button(action: onMove) {
                    Label("移动到...", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(UIConstants.blue)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .cardStyle()
    }
}
