import Foundation

/// 闹钟（周期性提醒）模型
struct Alarm: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var content: String
    let time: String         // HH:MM 触发时间
    let recurrence: String?  // daily/weekly/monthly
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content, time, recurrence
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 时间显示（HH:MM）
    var timeDisplay: String {
        time.count >= 5 ? String(time.prefix(5)) : time
    }

    /// 周期中文描述
    var recurrenceLabel: String {
        switch recurrence {
        case "weekly": return "每周"
        case "monthly": return "每月"
        default: return "每天"
        }
    }

    /// 转为 NoteFile，用于导航到详情页
    func toNoteFile() -> NoteFile {
        NoteFile(
            id: id, name: name, content: content,
            parentId: nil, type: "alarm",
            date: "", time: time, recurrence: recurrence,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
