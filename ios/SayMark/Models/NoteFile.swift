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
    let recurrenceEndDate: String  // 周期结束日期 YYYY-MM-DD，空=无限
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content, type, date, time
        case reminderMinutes = "reminder_minutes"
        case recurrence
        case recurrenceEndDate = "recurrence_end_date"
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

    /// 自定义重复间隔值（从 recurrence 字段解析，"custom:5:days" → 5）
    var repeatIntervalValue: Int? {
        guard let r = recurrence, r.hasPrefix("custom:") else { return nil }
        let parts = r.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        return Int(parts[1])
    }

    /// 自定义重复间隔单位（从 recurrence 字段解析，"custom:5:days" → "days"）
    var repeatIntervalUnit: String? {
        guard let r = recurrence, r.hasPrefix("custom:") else { return nil }
        let parts = r.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        return parts[2]
    }

    /// 构建自定义重复字符串
    static func recurrenceString(value: Int, unit: String) -> String {
        return "custom:\(value):\(unit)"
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
