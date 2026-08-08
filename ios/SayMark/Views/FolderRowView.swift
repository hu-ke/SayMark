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

    /// 统计该文件夹下的文件总数（含子文件夹）
    private var totalFiles: Int {
        countFiles(in: node)
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newValue in
                if newValue { expanded.insert(node.folder.id) }
                else { expanded.remove(node.folder.id) }
            }
        )) {
            // 子文件夹
            ForEach(node.children) { child in
                FolderRowView(node: child, viewModel: viewModel, expanded: $expanded)
            }
            // 文件
            ForEach(node.files) { file in
                FileRowView(file: file, viewModel: viewModel)
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                Text(node.folder.name)
                Spacer()
            }
        }
        .contextMenu {
            Button("重命名") { showRename = true }
            Button("删除", role: .destructive) { showDeleteConfirm = true }
            Button("新建子项") { showNewSubItem = true }
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
            .tint(.blue)
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
