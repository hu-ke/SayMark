import Foundation

/// 笔记文件模型
struct NoteFile: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var content: String
    let parentId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
