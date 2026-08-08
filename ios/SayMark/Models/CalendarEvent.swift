import Foundation

/// 日程事件模型（底层统一为 type=event 的文件，与 NoteFile 同源）
struct CalendarEvent: Codable, Identifiable, Hashable {
    let id: String
    let name: String       // 文件名称（等同于旧 title）
    let date: String       // YYYY-MM-DD
    let time: String       // HH:MM 或空
    let content: String
    let type: String       // "event"
    let parentId: String   // 所在文件夹 id
    let reminderMinutes: Int?  // 提前多少分钟提醒
    let recurrence: String?    // 周期
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, date, time, content, type
        case parentId = "parent_id"
        case reminderMinutes = "reminder_minutes"
        case recurrence
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 向后兼容 title 字段
    var title: String { name }

    /// 时间显示（如 "14:00" 或 ""）
    var timeDisplay: String {
        guard !time.isEmpty else { return "" }
        return time
    }
}

/// 月历摘要项（某天有几个日程）
struct MonthSummaryItem: Codable, Identifiable {
    var id: String { date }
    let date: String
    let count: Int
}
