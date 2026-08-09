import SwiftUI

struct FolderRowView: View {
    let node: TreeNode
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var expanded: Set<String>
    @State private var showRename = false
    @State private var showNewSubItem = false
    @State private var showDeleteConfirm = false

    private var isExpanded: Bool {
        expanded.contains(node.folder.id)
    }

    private var totalFiles: Int {
        countFiles(in: node)
    }

    private var isEmpty: Bool {
        node.children.isEmpty && node.files.isEmpty
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newValue in
                if newValue { expanded.insert(node.folder.id) }
                else { expanded.remove(node.folder.id) }
            }
        )) {
            if isEmpty {
                HStack {
                    Spacer()
                    Text("空文件夹")
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.md)
            } else {
                ForEach(node.children) { child in
                    FolderRowView(node: child, viewModel: viewModel, expanded: $expanded)
                }
                ForEach(node.files) { file in
                    FileRowView(file: file, viewModel: viewModel)
                }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Color.primary)

                Text(node.folder.name)
                    .font(DesignTokens.Font.body)

                Spacer()

                if totalFiles > 0 {
                    Text("\(totalFiles)")
                        .font(DesignTokens.Font.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(DesignTokens.Color.bgSecondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button { showRename = true } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button { showNewSubItem = true } label: {
                Label("新建子项", systemImage: "plus")
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            .tint(DesignTokens.Color.primary)
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(initialName: node.folder.name) { newName in
                Task { await viewModel.renameFolder(id: node.folder.id, name: newName) }
            }
        }
        .sheet(isPresented: $showNewSubItem) {
            NewItemSheet(viewModel: viewModel, parentId: node.folder.id)
        }
        .confirmationDialog(
            "确定删除文件夹？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteFolder(id: node.folder.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(totalFiles > 0
                ? "将删除「\(node.folder.name)」及其内部 \(totalFiles) 个文件。此操作不可撤销。"
                : "将删除空文件夹「\(node.folder.name)」。")
        }
    }

    private func countFiles(in node: TreeNode) -> Int {
        node.files.count + node.children.reduce(0) { $0 + countFiles(in: $1) }
    }
}
