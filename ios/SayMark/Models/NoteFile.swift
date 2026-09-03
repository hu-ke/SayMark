import Foundation

/// 笔记文件模型
/// 注意：目录树接口返回的文件不含 content，故此处设为可选；单文件接口会填充。
struct NoteFile: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var content: String?
    let parentId: String?
    let type: String  // "note" | "appointment" | "alarm"
    let date: String  // YYYY-MM-DD，仅 appointment 有值
    let time: String  // appointment=开始时间；alarm=周期触发时间
    let recurrence: String?    // 仅 alarm：daily/weekly/monthly
    let createdAt: String
    let updatedAt: String
    let todoTotal: Int = 0
    let todoDone: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name, content, type, date, time, recurrence
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case todoTotal = "todo_total"
        case todoDone = "todo_done"
    }

    /// 是否为笔记
    var isNote: Bool { type == "note" }

    /// 是否为安排（一次性）
    var isAppointment: Bool { type == "appointment" }

    /// 是否为闹钟（周期性）
    var isAlarm: Bool { type == "alarm" }

    /// 时间显示（HH:MM）
    var timeDisplay: String {
        guard !time.isEmpty else { return "" }
        return time.count >= 5 ? String(time.prefix(5)) : time
    }

    /// 周期中文描述（闹钟）
    var recurrenceLabel: String {
        switch recurrence {
        case "weekly": return "每周"
        case "monthly": return "每月"
        default: return "每天"
        }
    }
}

/// 归档文件模型（GET /api/archive）
struct ArchivedFile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let archivedPath: String
    let todoTotal: Int
    let todoDone: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case archivedPath = "archived_path"
        case todoTotal = "todo_total"
        case todoDone = "todo_done"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
