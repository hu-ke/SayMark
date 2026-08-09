import Foundation
import Combine

/// 笔记详情视图模型
@MainActor
final class NoteViewModel: ObservableObject {
    @Published var note: NoteFile?
    @Published var loading: Bool = false
    @Published var error: String?

    var fileId: String = ""
    private let api = APIClient.shared

    init() {}

    init(note: NoteFile) {
        self.note = note
        self.fileId = note.id
    }

    func reload() async {
        guard !fileId.isEmpty else { return }
        loading = true
        do {
            note = try await api.getFile(id: fileId)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// 保存名称与内容（仅当变更时调用对应接口）
    func save(name: String, content: String) async {
        guard let note else { return }
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
