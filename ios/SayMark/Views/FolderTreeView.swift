import SwiftUI

/// Figma 风格的文件列表视图：卡片式布局 + 空态插图 + FAB 录音按钮
struct FolderTreeView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var locateFolderId: String?
    @Binding var showNewItem: Bool
    @Binding var showChat: Bool
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
            } else if viewModel.tree.isEmpty {
                emptyState
            } else {
                fileListContent
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

    // MARK: - 文件列表内容

    private var fileListContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.tree) { node in
                    CardView {
                        FolderRowView(node: node, viewModel: viewModel, expanded: $expanded)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 80) // FAB 上方留白
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.loadTree()
        }
    }

    // MARK: - 空状态（Figma 风格插图）

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            // 自定义插图：笔记本 + 话筒徽章
            ZStack {
                // 笔记本主体
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: 84, height: 94)
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 229/255, green: 229/255, blue: 234/255))
                            .frame(width: 10)
                    }
                    .overlay {
                        // 文本线
                        VStack(alignment: .leading, spacing: 7) {
                            TextLine(width: 48)
                            TextLine(width: 38)
                            TextLine(width: 44)
                            TextLine(width: 32)
                        }
                        .padding(.leading, 12)
                    }

                // 话筒徽章
                Circle()
                    .fill(DesignColor.blue)
                    .frame(width: 44, height: 44)
                    .shadow(color: DesignColor.blue.opacity(0.4), radius: 8, y: 4)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 42, y: 48)
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                Text("还没有笔记")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignColor.label)

                Text("按住话筒开始说话吧，AI 会自动整理成结构化笔记")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignColor.label3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - 工具

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

// MARK: - 卡片包装

/// 白色圆角卡片容器（Figma `lcard`）
private struct CardView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DesignColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 文本线（空状态插图的装饰）

private struct TextLine: View {
    let width: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(red: 209/255, green: 209/255, blue: 214/255))
            .frame(width: width, height: 5)
    }
}
