import SwiftUI

struct FolderRowView: View {
    // 功能已整合到 FolderTreeView.swift 中的 FolderCard / SubFolderRow
    // 此文件保留以确保现有引用不报错
    var body: some View {
        EmptyView()
    }
}

struct FolderRowViewOld: View {
    let node: TreeNode
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var isExpanded = false

    var body: some View {
        EmptyView()
    }
}
