import SwiftUI

struct FolderTreeView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var locateFolderId: String?
    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack {
            if viewModel.loading && viewModel.tree.isEmpty {
                ProgressView("加载中...")
            } else if let error = viewModel.error, viewModel.tree.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.loadTree() }
                    }
                }
            } else {
                List {
                    ForEach(viewModel.tree) { node in
                        FolderRowView(node: node, viewModel: viewModel, expanded: $expanded)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadTree()
                }
            }
        }
        .navigationDestination(for: NoteFile.self) { file in
            FileDetailView(note: file, viewModel: viewModel)
        }
        .alert("出错了", isPresented: Binding(
            get: { viewModel.error != nil && !viewModel.tree.isEmpty },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .onChange(of: locateFolderId) { _, newValue in
            if let id = newValue {
                expand(to: id)
            }
        }
    }

    /// 展开到目标文件夹（展开其全部祖先）
    private func expand(to folderId: String) {
        guard let path = findPath(in: viewModel.tree, target: folderId) else { return }
        for id in path {
            expanded.insert(id)
        }
    }

    /// 查找从根到目标文件夹的路径（返回目标所有祖先的 id）
    private func findPath(in nodes: [TreeNode], target: String) -> [String]? {
        for node in nodes {
            if node.folder.id == target {
                return []
            }
            if let sub = findPath(in: node.children, target: target) {
                return [node.folder.id] + sub
            }
        }
        return nil
    }
}
