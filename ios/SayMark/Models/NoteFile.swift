import Foundation

/// 笔记文件模型
/// 注意：目录树接口返回的文件不含 content，故此处设为可选；单文件接口会填充。
struct NoteFile: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var content: String?
    let parentId: String
    let type: String  // "note" 或 "event"
    let date: String  // YYYY-MM-DD，仅 event 类型有值
    let time: String  // HH:MM，仅 event 类型有值
    let reminderMinutes: Int?  // 提前多少分钟提醒，nil 表示无提醒
    let recurrence: String?    // null/""=一次性，"daily"/"weekly"/"monthly"
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content, type, date, time
        case reminderMinutes = "reminder_minutes"
        case recurrence
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 是否为日程类型
    var isEvent: Bool { type == "event" }

    /// 是否有提醒
    var hasReminder: Bool { reminderMinutes != nil }

    /// 是否为周期性提醒
    var isRecurring: Bool {
        guard let r = recurrence, !r.isEmpty else { return false }
        return true
    }

    /// 周期中文描述
    var recurrenceLabel: String {
        switch recurrence {
        case "daily": return "每天"
        case "weekly": return "每周"
        case "monthly": return "每月"
        default: return ""
        }
    }
}
