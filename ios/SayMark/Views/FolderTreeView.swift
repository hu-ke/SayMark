import SwiftUI

enum DragPayload {
    static func file(_ id: String) -> String { "file:\(id)" }
    static func folder(_ id: String) -> String { "folder:\(id)" }
}

/// 记录每个文件夹「+」按钮的位置，用于把添加菜单定位到按钮附近
struct AddButtonAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

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
    @State private var addPopoverFolderId: String? = nil
    @State private var addPopoverFolderName: String = ""
    @State private var showNewItem = false
    @State private var pushNewItemParentId: String? = nil
    @State private var pushNewItemType: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义导航栏
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Button {
                            pushNewItemParentId = nil
                            pushNewItemType = "folder"
                            showNewItem = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(UIConstants.blue)
                                .frame(width: 32, height: 32)
                                .background(UIConstants.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button(action: onChat) {
                            TabIcon(type: "chat", size: 18, color: UIConstants.blue, strokeWidth: 2)
                                .frame(width: 32, height: 32)
                                .background(UIConstants.blue.opacity(0.1))
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
                    destination: NewItemSheet(viewModel: viewModel, parentId: pushNewItemParentId, preSelectedType: pushNewItemType),
                    isActive: Binding(
                        get: { showNewItem },
                        set: { if !$0 { showNewItem = false; pushNewItemParentId = nil; pushNewItemType = nil } }
                    )
                ) { EmptyView() }
            )
        }
        // 文件夹添加菜单浮层（定位到「+」按钮附近）
        .overlayPreferenceValue(AddButtonAnchorKey.self) { anchors in
            if let folderId = addPopoverFolderId, let anchor = anchors[folderId] {
                GeometryReader { proxy in
                    FolderAddMenuOverlay(
                        folderName: addPopoverFolderName,
                        anchorRect: proxy[anchor],
                        onDismiss: { addPopoverFolderId = nil },
                        onAddFile: {
                            addPopoverFolderId = nil
                            pushNewItemParentId = folderId
                            pushNewItemType = "file"
                            showNewItem = true
                        },
                        onNewDir: {
                            addPopoverFolderId = nil
                            pushNewItemParentId = folderId
                            pushNewItemType = "folder"
                            showNewItem = true
                        }
                    )
                }
            }
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

    // MARK: - Header Helpers
    private var todayDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    private var pageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayDateString)
                    .font(.system(size: 22, weight: .bold))
                    .kerning(0.2)
                    .foregroundColor(UIConstants.label)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 0) {
            pageHeader

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
            }

            Spacer()
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageHeader

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
                            deleteIsFolder: $deleteIsFolder,
                            addPopoverFolderId: $addPopoverFolderId,
                            onAddTap: { id, name in
                                addPopoverFolderId = id
                                addPopoverFolderName = name
                            }
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
    @Binding var addPopoverFolderId: String?
    var onAddTap: ((String, String) -> Void)? = nil

    var isAddMenuOpen: Bool { addPopoverFolderId == node.id }

    @State private var isDropTargeted = false

    var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            // 文件夹标题行（含左滑删除）
            folderHeaderRow
                .background(UIConstants.card)

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
                        deleteIsFolder: $deleteIsFolder,
                        isAddMenuOpen: addPopoverFolderId == child.id,
                        onAddTap: onAddTap
                    )
                    .padding(.leading, 20)
                }
            }
        }
        .cardStyle()
    }

    private var folderHeaderRow: some View {
        ZStack(alignment: .trailing) {
            // 删除按钮（左滑后露出，覆盖在行的右侧）
            DeleteSwipeButton {
                deleteTargetId = node.id
                deleteTargetName = node.name
                deleteIsFolder = true
                showDeleteAlert = true
                swipedRow = nil
            }
            .opacity(swipedRow == node.id ? 1 : 0)

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
                    Button {
                        onAddTap?(node.id, node.name)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isAddMenuOpen ? .white : UIConstants.blue)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(isAddMenuOpen ? UIConstants.blue : UIConstants.blue.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .anchorPreference(key: AddButtonAnchorKey.self, value: .bounds) { [node.id: $0] }
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
            .background(UIConstants.card)
            .offset(x: swipedRow == node.id ? -72 : 0)
            .draggable(DragPayload.folder(node.id))
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let w = value.translation.width
                        let h = value.translation.height
                        if w < -30 && abs(w) > abs(h) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                swipedRow = node.id
                            }
                        }
                    }
            )
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                Task { await viewModel.handleDrop(payload: payload, targetFolderId: node.id) }
                return true
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDropTargeted = targeted
                }
            }
            .background(isDropTargeted ? UIConstants.blue.opacity(0.14) : Color.clear)
        }
        .frame(minHeight: 44)
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
    var isAddMenuOpen: Bool = false
    var onAddTap: ((String, String) -> Void)? = nil

    @State private var isDropTargeted = false
    var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ZStack(alignment: .trailing) {
                // 删除按钮（左滑后露出，覆盖在行的右侧）
                DeleteSwipeButton {
                    deleteTargetId = node.id
                    deleteTargetName = node.name
                    deleteIsFolder = true
                    showDeleteAlert = true
                    swipedRow = nil
                }
                .opacity(swipedRow == node.id ? 1 : 0)

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
                        Button {
                            onAddTap?(node.id, node.name)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isAddMenuOpen ? .white : UIConstants.blue)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(isAddMenuOpen ? UIConstants.blue : UIConstants.blue.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .anchorPreference(key: AddButtonAnchorKey.self, value: .bounds) { [node.id: $0] }
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
                .background(UIConstants.card)
                .offset(x: swipedRow == node.id ? -72 : 0)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let w = value.translation.width
                            let h = value.translation.height
                            if w < -30 && abs(w) > abs(h) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    swipedRow = node.id
                                }
                            }
                        }
                )
                .draggable(DragPayload.folder(node.id))
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    Task { await viewModel.handleDrop(payload: payload, targetFolderId: node.id) }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isDropTargeted = targeted
                    }
                }
                .background(isDropTargeted ? UIConstants.blue.opacity(0.14) : Color.clear)
            }
            .frame(minHeight: 44)

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
    }
}

// MARK: - Delete Swipe Button
struct DeleteSwipeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "trash").font(.system(size: 14))
                Text("删除").font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(width: 72, height: 44)
            .background(UIConstants.red)
        }
        .buttonStyle(.plain)
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

    @State private var isDropTargeted = false
    @State private var navigate = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ZStack(alignment: .trailing) {
                // 删除按钮（左滑后露出，覆盖在行的右侧）
                DeleteSwipeButton {
                    deleteTargetId = file.id
                    deleteTargetName = file.name
                    deleteIsFolder = false
                    showDeleteAlert = true
                    swipedRow = nil
                }
                .opacity(isSwiped ? 1 : 0)

                // 行内容：点击进入详情
                Button {
                    swipedRow = nil
                    navigate = true
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .background(UIConstants.card)
                .offset(x: isSwiped ? -72 : 0)
                .draggable(DragPayload.file(file.id))
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let w = value.translation.width
                            let h = value.translation.height
                            if w < -30 && abs(w) > abs(h) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    swipedRow = file.id
                                }
                            }
                        }
                )
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    Task { await viewModel.handleFileSwap(payload: payload, targetId: file.id) }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isDropTargeted = targeted
                    }
                }
                .background(isDropTargeted ? UIConstants.orange.opacity(0.14) : Color.clear)
            }
            .frame(minHeight: 44)

            // 隐藏导航链接（与点击手势解耦，避免左滑误触发导航）
            NavigationLink(
                destination: FileDetailView(fileId: file.id, fileName: file.name, folderTreeViewModel: viewModel),
                isActive: $navigate
            ) { EmptyView() }
            .hidden()
        }
        .background(UIConstants.card)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            RowIcon(
                iconType: "doc",
                color: UIConstants.label3
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatTime(file.createdAt))
                    .font(.system(size: 13))
                    .foregroundColor(UIConstants.label3)
                    .kerning(-0.08)
            }
            Spacer()
            if file.todoTotal > 0 {
                Text("\(file.todoDone)/\(file.todoTotal)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(file.todoDone == file.todoTotal ? UIConstants.green : UIConstants.label3)
                    .kerning(-0.08)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(UIConstants.label3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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

// MARK: - Folder Add Menu Overlay (positioned near the tapped "+" button)
struct FolderAddMenuOverlay: View {
    let folderName: String
    let anchorRect: CGRect
    let onDismiss: () -> Void
    let onAddFile: () -> Void
    let onNewDir: () -> Void

    private let cardWidth: CGFloat = 260
    private let cardHeight: CGFloat = 160

    var body: some View {
        ZStack {
            // Invisible backdrop to dismiss
            Color.black.opacity(0.01)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            GeometryReader { geo in
                card
                    .frame(width: cardWidth, height: cardHeight)
                    .position(
                        x: cardCenterX(in: geo.size),
                        y: cardCenterY(in: geo.size)
                    )
            }
        }
    }

    private func cardCenterX(in size: CGSize) -> CGFloat {
        var left = anchorRect.maxX - cardWidth
        left = min(max(left, 16), size.width - cardWidth - 16)
        return left + cardWidth / 2
    }

    private func cardCenterY(in size: CGSize) -> CGFloat {
        let belowCenter = anchorRect.maxY + 8 + cardHeight / 2
        if belowCenter < size.height - 20 {
            return belowCenter
        }
        return anchorRect.minY - 8 - cardHeight / 2
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加到「\(folderName)」")
                    .font(.system(size: 12))
                    .foregroundColor(UIConstants.label3)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle()
                .fill(UIConstants.separator)
                .frame(height: 0.5)

            Button(action: onAddFile) {
                HStack(spacing: 12) {
                    RowIcon(systemName: "doc.text.fill", color: UIConstants.label3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("添加文件")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(UIConstants.label)
                        Text("创建新笔记")
                            .font(.system(size: 12))
                            .foregroundColor(UIConstants.label3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(UIConstants.separator)
                .frame(height: 0.5)

            Button(action: onNewDir) {
                HStack(spacing: 12) {
                    RowIcon(systemName: "folder.fill", color: UIConstants.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("新建目录")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(UIConstants.label)
                        Text("在此文件夹下创建子目录")
                            .font(.system(size: 12))
                            .foregroundColor(UIConstants.label3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            Color.white.opacity(0.96)
                .background(Material.regular)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }
}
