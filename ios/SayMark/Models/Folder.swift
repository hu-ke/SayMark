import Foundation

/// 文件夹模型
struct Folder: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let parentId: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
