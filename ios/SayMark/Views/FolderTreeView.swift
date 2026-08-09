import SwiftUI

struct FolderTreeView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var locateFolderId: String?
    @State private var expanded: Set<String> = []

    var body: some View {
        ZStack {
            if viewModel.loading && viewModel.tree.isEmpty {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载中...")
                        .font(DesignTokens.Font.subheadline)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
            } else if let error = viewModel.error, viewModel.tree.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.loadTree() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.tree.isEmpty {
                ContentUnavailableView {
                    Label("还没有笔记", systemImage: "doc.text")
                        .font(DesignTokens.Font.title3)
                } description: {
                    Text("点击右上角 + 创建文件夹和笔记\n或长按录音按钮开始语音记录")
                } actions: {
                    Button {
                        Task { await viewModel.loadTree() }
                    } label: {
                        Text("刷新")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(viewModel.tree) { node in
                        FolderRowView(node: node, viewModel: viewModel, expanded: $expanded)
                    }
                }
                .listStyle(.plain)
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

    private func expand(to folderId: String) {
        guard let path = findPath(in: viewModel.tree, target: folderId) else { return }
        for id in path {
            expanded.insert(id)
        }
    }

    private func findPath(in nodes: [TreeNode], target: String) -> [String]? {
        for node in nodes {
            if node.folder.id == target { return [] }
            if let sub = findPath(in: node.children, target: target) {
                return [node.folder.id] + sub
            }
        }
        return nil
    }
}
