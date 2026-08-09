import SwiftUI

struct FolderTreeView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var locateFolderId: String?

    var onNote: () -> Void
    var onChat: () -> Void
    var onRecord: () -> Void

    @State private var expandedFolders: Set<String> = []
    @State private var swipedRow: String? = nil
    @State private var showDeleteAlert = false
    @State private var deleteTargetId: String?
    @State private var deleteTargetName: String?
    @State private var deleteIsFolder = false
    @State private var pushNewItem = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义导航栏
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: onChat) {
                            TabIcon(type: "chat", size: 18, color: UIConstants.blue, strokeWidth: 2)
                                .frame(width: 32, height: 32)
                                .background(UIConstants.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            pushNewItem = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(UIConstants.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                // 内容区
                if viewModel.loading && viewModel.tree.isEmpty {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if viewModel.tree.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .background(UIConstants.background)
            .refreshable {
                await viewModel.loadTree()
            }
            // 隐藏的 NavigationLink，用于 push 到新建页面
            .background(
                NavigationLink(
                    destination: NewItemSheet(viewModel: viewModel, parentId: nil),
                    isActive: $pushNewItem
                ) { EmptyView() }
            )
        }
        // 自定义删除确认弹窗
        .overlay {
            if showDeleteAlert {
                DeleteConfirmDialog(
                    isFolder: deleteIsFolder,
                    name: deleteTargetName ?? "",
                    onCancel: { showDeleteAlert = false },
                    onDelete: {
                        guard let id = deleteTargetId else { return }
                        showDeleteAlert = false
                        Task {
                            if deleteIsFolder {
                                await viewModel.deleteFolder(id: id)
                            } else {
                                await viewModel.deleteFile(id: id)
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 0) {
            // 大标题
            HStack {
                Text("SayMark")
                    .font(.system(size: 34, weight: .bold))
                    .kerning(0.37)
                    .foregroundColor(UIConstants.label)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                Spacer()
            }

            Spacer()

            VStack(spacing: 14) {
                // 笔记本插图
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .frame(width: 84, height: 94)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                    // 书脊
                    Rectangle()
                        .fill(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .frame(width: 10, height: 94)
                    // 文字模拟行
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color(red: 0.820, green: 0.820, blue: 0.839))
                            .frame(width: 48, height: 5)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color(red: 0.820, green: 0.820, blue: 0.839))
                            .frame(width: 38, height: 5)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color(red: 0.820, green: 0.820, blue: 0.839))
                            .frame(width: 44, height: 5)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color(red: 0.820, green: 0.820, blue: 0.839))
                            .frame(width: 32, height: 5)
                    }
                    .padding(.leading, 40)

                    // 麦克风徽章
                    Circle()
                        .fill(UIConstants.blue)
                        .frame(width: 44, height: 44)
                        .shadow(color: UIConstants.blue.opacity(0.45), radius: 8, y: 6)
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                        .offset(x: 38, y: 42)
                }

                VStack(spacing: 4) {
                    Text("还没有笔记")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(UIConstants.label)
                        .kerning(-0.5)
                    Text("按住话筒开始说话吧，AI 会自动整理成结构化笔记")
                        .font(.system(size: 15))
                        .foregroundColor(UIConstants.label3)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .kerning(-0.24)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 8)

                Button(action: onRecord) {
                    Text("开始录音")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(UIConstants.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: UIConstants.blue.opacity(0.33), radius: 16, y: 4)
                }
                .padding(.top, 12)
            }

            Spacer()
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 大标题
                HStack {
                    Text("SayMark")
                        .font(.system(size: 34, weight: .bold))
                        .kerning(0.37)
                        .foregroundColor(UIConstants.label)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                    Spacer()
                }

                // 卡片列表
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.tree.enumerated()), id: \.element.id) { index, node in
                        FolderCard(
                            node: node,
                            colorIndex: index,
                            expandedFolders: $expandedFolders,
                            swipedRow: $swipedRow,
                            viewModel: viewModel,
                            showDeleteAlert: $showDeleteAlert,
                            deleteTargetId: $deleteTargetId,
                            deleteTargetName: $deleteTargetName,
                        deleteIsFolder: $deleteIsFolder
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // 底部留白给 FAB + TabBar
                Color.clear.frame(height: 100)
            }
        }
    }
}

// MARK: - Folder Card
struct FolderCard: View {
    let node: TreeNode
    let colorIndex: Int
    @Binding var expandedFolders: Set<String>
    @Binding var swipedRow: String?
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var showDeleteAlert: Bool
    @Binding var deleteTargetId: String?
    @Binding var deleteTargetName: String?
    @Binding var deleteIsFolder: Bool

    @State private var showRenameSheet = false

    var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            // 文件夹标题行
            folderHeaderRow
                .background(UIConstants.card)

            // Swipe 操作
            if swipedRow == node.id {
                swipeActions(for: node.id, name: node.name, isFolder: true)
            }

            // 展开的子内容
            if isExpanded {
                Divider()
                ForEach(node.files) { file in
                    FileRowCard(
                        file: file,
                        isSwiped: swipedRow == file.id,
                        viewModel: viewModel,
                        swipedRow: $swipedRow,
                        showDeleteAlert: $showDeleteAlert,
                        deleteTargetId: $deleteTargetId,
                        deleteTargetName: $deleteTargetName,
                        deleteIsFolder: $deleteIsFolder
                    )
                    .padding(.leading, 20)
                }
                ForEach(Array(node.children.enumerated()), id: \.element.id) { childIndex, child in
                    SubFolderRow(
                        node: child,
                        colorIndex: childIndex,
                        expandedFolders: $expandedFolders,
                        swipedRow: $swipedRow,
                        viewModel: viewModel,
                        showDeleteAlert: $showDeleteAlert,
                        deleteTargetId: $deleteTargetId,
                        deleteTargetName: $deleteTargetName,
                        deleteIsFolder: $deleteIsFolder
                    )
                }
            }
        }
        .cardStyle()
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(
                title: "重命名文件夹",
                currentName: node.name
            ) { newName in
                Task { await viewModel.renameFolder(id: node.id, name: newName) }
            }
        }
    }

    private var folderHeaderRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedFolders.remove(node.id)
                } else {
                    expandedFolders.insert(node.id)
                }
                swipedRow = nil
            }
        } label: {
            HStack(spacing: 12) {
                RowIcon(
                    iconType: "folder",
                    color: UIConstants.folderColors[colorIndex % UIConstants.folderColors.count]
                )
                Text(node.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                Spacer()
                if !isExpanded {
                    let count = node.files.count + node.children.reduce(0) { $0 + $1.files.count + $1.children.reduce(0) { $0 + $1.files.count } }
                    Text("\(count)项")
                        .font(.system(size: 13))
                        .foregroundColor(UIConstants.label3)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(UIConstants.label3)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        swipedRow = swipedRow == node.id ? nil : node.id
                    }
                }
        )
        .contextMenu {
            Button {
                deleteTargetId = node.id
                deleteTargetName = node.name
                deleteIsFolder = true
                showDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                showRenameSheet = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
        }
    }

    private func swipeActions(for id: String, name: String, isFolder: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                swipedRow = nil
                showRenameSheet = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                    Text("重命名")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 72, height: 44)
                .background(UIConstants.blue)
            }

            Button {
                deleteTargetId = id
                deleteTargetName = name
                deleteIsFolder = isFolder
                showDeleteAlert = true
                swipedRow = nil
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                    Text("删除")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 72, height: 44)
                .background(UIConstants.red)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

// MARK: - Sub Folder Row
struct SubFolderRow: View {
    let node: TreeNode
    let colorIndex: Int
    @Binding var expandedFolders: Set<String>
    @Binding var swipedRow: String?
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var showDeleteAlert: Bool
    @Binding var deleteTargetId: String?
    @Binding var deleteTargetName: String?
    @Binding var deleteIsFolder: Bool

    @State private var showRenameSheet = false
    var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedFolders.remove(node.id)
                    } else {
                        expandedFolders.insert(node.id)
                    }
                    swipedRow = nil
                }
            } label: {
                HStack(spacing: 12) {
                    RowIcon(iconType: "folder", color: UIConstants.folderColors[colorIndex % UIConstants.folderColors.count])
                    Text(node.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(UIConstants.label)
                        .kerning(-0.41)
                    Spacer()
                    if !isExpanded {
                        Text("\(node.files.count)项")
                            .font(.system(size: 13))
                            .foregroundColor(UIConstants.label3)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(UIConstants.label3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 36)
            .contextMenu {
                Button {
                    deleteTargetId = node.id
                    deleteTargetName = node.name
                    deleteIsFolder = true
                    showDeleteAlert = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Button {
                    showRenameSheet = true
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
            }

            if swipedRow == node.id {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        swipedRow = nil
                        showRenameSheet = true
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "pencil").font(.system(size: 14))
                            Text("重命名").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .background(UIConstants.blue)
                    }
                    Button {
                        deleteTargetId = node.id
                        deleteTargetName = node.name
                        deleteIsFolder = true
                        showDeleteAlert = true
                        swipedRow = nil
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "trash").font(.system(size: 14))
                            Text("删除").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .background(UIConstants.red)
                    }
                }
            }

            if isExpanded {
                Divider()
                ForEach(node.files) { file in
                    FileRowCard(
                        file: file,
                        isSwiped: swipedRow == file.id,
                        viewModel: viewModel,
                        swipedRow: $swipedRow,
                        showDeleteAlert: $showDeleteAlert,
                        deleteTargetId: $deleteTargetId,
                        deleteTargetName: $deleteTargetName,
                        deleteIsFolder: $deleteIsFolder
                    )
                    .padding(.leading, 20)
                }
            }
        }
        .background(UIConstants.card)
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(title: "重命名文件夹", currentName: node.name) { newName in
                Task { await viewModel.renameFolder(id: node.id, name: newName) }
            }
        }
    }
}

// MARK: - File Row Card
struct FileRowCard: View {
    let file: NoteFile
    let isSwiped: Bool
    @ObservedObject var viewModel: FolderTreeViewModel
    @Binding var swipedRow: String?
    @Binding var showDeleteAlert: Bool
    @Binding var deleteTargetId: String?
    @Binding var deleteTargetName: String?
    @Binding var deleteIsFolder: Bool

    @State private var showRenameSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            NavigationLink {
                FileDetailView(fileId: file.id, fileName: file.name)
            } label: {
                HStack(spacing: 12) {
                    RowIcon(
                        iconType: file.isEvent ? "cal" : "doc",
                        color: file.isEvent ? UIConstants.orange : UIConstants.label3
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(file.name)
                                .font(.system(size: 17))
                                .foregroundColor(UIConstants.label)
                                .kerning(-0.41)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if file.isEvent {
                                CapsuleBadge(text: "日程")
                            }
                        }
                        Text(formatTime(file.createdAt))
                            .font(.system(size: 13))
                            .foregroundColor(UIConstants.label3)
                            .kerning(-0.08)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(UIConstants.label3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            swipedRow = swipedRow == file.id ? nil : file.id
                        }
                    }
            )
            .contextMenu {
                Button {
                    deleteTargetId = file.id
                    deleteTargetName = file.name
                    deleteIsFolder = false
                    showDeleteAlert = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Button {
                    showRenameSheet = true
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
            }

            if isSwiped {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        swipedRow = nil
                        showRenameSheet = true
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "pencil").font(.system(size: 13))
                            Text("重命名").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .background(UIConstants.blue)
                    }
                    Button {
                        deleteTargetId = file.id
                        deleteTargetName = file.name
                        showDeleteAlert = true
                        swipedRow = nil
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "trash").font(.system(size: 13))
                            Text("删除").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .background(UIConstants.red)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(UIConstants.card)
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(title: "重命名文件", currentName: file.name) { newName in
                Task { await viewModel.renameFile(id: file.id, name: newName) }
            }
        }
    }

    private func formatTime(_ time: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: time) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: time) else { return "" }
            return formatDisplay(date: date)
        }
        return formatDisplay(date: date)
    }

    private func formatDisplay(date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "今天 \(f.string(from: date))"
        } else if cal.isDateInYesterday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "昨天 \(f.string(from: date))"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MM月dd日"
            return f.string(from: date)
        }
    }
}

// MARK: - Delete Confirm Dialog (matching "iOS App UI Redesign")
struct DeleteConfirmDialog: View {
    let isFolder: Bool
    let name: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(isFolder ? "确定删除文件夹？" : "确定删除文件？")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(UIConstants.label)
                        .kerning(-0.41)
                    Text("将删除「\(name)」\(isFolder ? "及其内部文件" : "")。此操作不可撤销。")
                        .font(.system(size: 13))
                        .foregroundColor(UIConstants.label3)
                        .kerning(-0.08)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 16)

                HDSeparator()

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 17))
                            .foregroundColor(UIConstants.blue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }

                    Rectangle()
                        .fill(UIConstants.separator)
                        .frame(width: 0.5, height: 44)

                    Button(action: onDelete) {
                        Text("删除")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(UIConstants.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .frame(width: 270)
            .background(
                UIConstants.background.opacity(0.98)
                    .background(Material.ultraThin)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.45), radius: 64, y: 24)
        }
    }
}
