import Foundation
import Combine

/// 目录树视图模型
@MainActor
final class FolderTreeViewModel: ObservableObject {
    @Published var tree: [TreeNode] = []
    @Published var loading: Bool = false
    @Published var error: String?
    @Published var selectedFolderId: String?  // 定位文件夹
    @Published var hideFloatingButton = false  // 进入详情页时隐藏浮动按钮
    @Published var hideTabBar = false  // 进入详情页时隐藏底部 Tab 栏

    private let api = APIClient.shared

    func loadTree() async {
        loading = true
        error = nil
        do {
            tree = try await api.getFolderTree()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func createFolder(name: String, parentId: String?) async {
        do {
            _ = try await api.createFolder(name: name, parentId: parentId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func renameFolder(id: String, name: String) async {
        do {
            try await api.renameFolder(id: id, name: name)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteFolder(id: String) async {
        do {
            try await api.deleteFolder(id: id)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createFile(name: String, content: String, parentId: String) async {
        do {
            _ = try await api.createFile(name: name, content: content, parentId: parentId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func renameFile(id: String, name: String?) async {
        do {
            try await api.renameFile(id: id, name: name)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteFile(id: String) async {
        do {
            try await api.deleteFile(id: id)
            await loadTree()
            await NotificationManager.shared.refreshFromServer()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func moveFile(id: String, targetFolderId: String) async {
        do {
            try await api.moveFile(id: id, targetFolderId: targetFolderId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func moveFolder(id: String, targetFolderId: String?) async {
        do {
            try await api.moveFolder(id: id, targetFolderId: targetFolderId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 处理拖拽落点：payload 形如 "file:<id>" 或 "folder:<id>"
    func handleDrop(payload: String, targetFolderId: String) async {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let kind = parts[0]
        let id = parts[1]
        guard id != targetFolderId else { return }
        if kind == "file" {
            await moveFile(id: id, targetFolderId: targetFolderId)
        } else if kind == "folder" {
            await moveFolder(id: id, targetFolderId: targetFolderId)
        }
    }

    /// 文件拖到另一个文件上：交换两者位置
    func handleFileSwap(payload: String, targetId: String) async {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "file" else { return }
        let sourceId = parts[1]
        guard sourceId != targetId else { return }
        do {
            try await api.reorder(type: "file", sourceId: sourceId, targetId: targetId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 定位到指定文件夹（设置选中，FolderTreeView 据此展开）
    func locate(folderId: String) {
        selectedFolderId = folderId
    }
}
