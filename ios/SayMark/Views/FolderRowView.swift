import SwiftUI

struct FolderRowView: View {
    let node: TreeNode
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var expanded: Set<String>
    @State private var showRename = false
    @State private var showNewSubItem = false

    private var isExpanded: Bool {
        expanded.contains(node.folder.id)
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
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteFolder(id: node.folder.id) }
            }
            Button("新建子项") { showNewSubItem = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.deleteFolder(id: node.folder.id) }
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
    }
}
