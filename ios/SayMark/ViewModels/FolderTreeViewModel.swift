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

    func createFile(name: String, content: String, parentId: String,
                    type: String = "note", date: String = "", time: String = "",
                    repeatIntervalValue: Int? = nil, repeatIntervalUnit: String? = nil) async {
        do {
            _ = try await api.createFile(name: name, content: content, parentId: parentId,
                                        type: type, date: date, time: time,
                                        repeatIntervalValue: repeatIntervalValue,
                                        repeatIntervalUnit: repeatIntervalUnit)
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

    func moveFolder(id: String, targetFolderId: String) async {
        do {
            try await api.moveFolder(id: id, targetFolderId: targetFolderId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func swapFile(id: String, targetId: String) async {
        do {
            try await api.swapFile(id: id, targetId: targetId)
            await loadTree()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func swapFolder(id: String, targetId: String) async {
        do {
            try await api.swapFolder(id: id, targetId: targetId)
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
