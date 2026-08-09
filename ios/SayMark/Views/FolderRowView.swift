import SwiftUI

/// Figma 风格的文件夹行，支持展开/折叠、彩色图标、项数统计
struct FolderRowView: View {
    let node: TreeNode
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var expanded: Set<String>
    @State private var showRename = false
    @State private var showNewSubItem = false
    @State private var showDeleteConfirm = false
    @State private var isExpanded: Bool

    /// 文件夹图标颜色（按位置轮替: 蓝→橙→绿）
    private var folderColor: Color {
        // 用 id 的 hash 来决定颜色，保证一致性
        let colors: [Color] = [DesignColor.blue, DesignColor.orange, DesignColor.green]
        let hash = abs(node.folder.id.hashValue)
        return colors[hash % colors.count]
    }

    /// 统计该文件夹下的文件总数（含子文件夹）
    private var totalFiles: Int {
        countFiles(in: node)
    }

    init(node: TreeNode, viewModel: FolderTreeViewModel, expanded: Binding<Set<String>>) {
        self.node = node
        self.viewModel = viewModel
        self._expanded = expanded
        self._isExpanded = State(initialValue: expanded.wrappedValue.contains(node.folder.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 文件夹头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expanded.remove(node.folder.id)
                    } else {
                        expanded.insert(node.folder.id)
                    }
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    // 彩色文件夹图标
                    RoundedRectangle(cornerRadius: 6)
                        .fill(folderColor)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }

                    Text(node.folder.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DesignColor.label)
                        .padding(.leading, 12)

                    Spacer()

                    // 折叠时显示项数
                    if !isExpanded {
                        Text("\(totalFiles)项")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignColor.label3)
                            .padding(.trailing, 4)
                    }

                    // 箭头动画
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignColor.label3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开的子内容
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(node.children) { child in
                        FolderRowView(node: child, viewModel: viewModel, expanded: $expanded)
                    }
                    ForEach(node.files) { file in
                        FileRowView(file: file, viewModel: viewModel)
                    }
                }
            }
        }
        .background(DesignColor.card)
        .contextMenu {
            Button {
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                showNewSubItem = true
            } label: {
                Label("新建子项", systemImage: "plus")
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
            .tint(DesignColor.blue)
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
