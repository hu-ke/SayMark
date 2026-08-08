import Foundation
import Combine

/// 笔记详情视图模型
@MainActor
final class NoteViewModel: ObservableObject {
    @Published var note: NoteFile
    @Published var loading: Bool = false
    @Published var error: String?

    private let api = APIClient.shared

    init(note: NoteFile) {
        self.note = note
    }

    func reload() async {
        loading = true
        do {
            note = try await api.getFile(id: note.id)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// 保存名称与内容（仅当变更时调用对应接口）
    func save(name: String, content: String) async {
        do {
            if name != note.name {
                try await api.renameFile(id: note.id, name: name)
            }
            if content != (note.content ?? "") {
                try await api.updateFileContent(id: note.id, content: content)
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
