import Foundation

/// 目录树节点
/// 后端返回扁平结构：文件夹字段 + children + files 同层。这里提供计算属性 folder 便于视图使用。
struct TreeNode: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let parentId: String?
    let createdAt: String
    let updatedAt: String
    var children: [TreeNode]
    var files: [NoteFile]

    /// 派生 Folder 对象，保持视图层 node.folder.xxx 用法不变
    var folder: Folder {
        Folder(id: id, name: name, parentId: parentId, createdAt: createdAt, updatedAt: updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, children, files
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// AI 指令返回结果
struct CommandResult: Codable {
    let action: String
    let success: Bool
    let message: String
    let data: AnyCodable?
}

/// 通用 JSON 值包装，用于解析 CommandResult.data（可能是字典、数组或标量）
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict
        } else if let arr = try? container.decode([AnyCodable].self) {
            self.value = arr
        } else if let str = try? container.decode(String.self) {
            self.value = str
        } else if let num = try? container.decode(Double.self) {
            self.value = num
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let dict as [String: AnyCodable]:
            try container.encode(dict)
        case let arr as [AnyCodable]:
            try container.encode(arr)
        case let str as String:
            try container.encode(str)
        case let num as Double:
            try container.encode(num)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }

    /// 转为字典（如果 data 是对象）
    var dictionaryValue: [String: Any]? {
        guard let dict = value as? [String: AnyCodable] else { return nil }
        return dict.mapValues { $0.anyValue }
    }

    /// 转为数组（如果 data 是数组）
    var arrayValue: [Any]? {
        guard let arr = value as? [AnyCodable] else { return nil }
        return arr.map { $0.anyValue }
    }

    /// 递归还原为原生 Swift 类型
    var anyValue: Any {
        switch value {
        case let dict as [String: AnyCodable]:
            return dict.mapValues { $0.anyValue }
        case let arr as [AnyCodable]:
            return arr.map { $0.anyValue }
        default:
            return value
        }
    }
}
