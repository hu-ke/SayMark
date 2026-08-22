import Foundation

/// 安排（一次性日程）模型
struct Appointment: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var content: String
    let date: String       // YYYY-MM-DD
    let time: String       // HH:MM 或空
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content, date, time
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 时间显示（如 "14:00" 或 ""）
    var timeDisplay: String {
        guard !time.isEmpty else { return "" }
        return time.count >= 5 ? String(time.prefix(5)) : time
    }

    /// 转为 NoteFile，用于导航到详情页
    func toNoteFile() -> NoteFile {
        NoteFile(
            id: id, name: name, content: content,
            parentId: nil, type: "appointment",
            date: date, time: time, recurrence: nil,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

/// 月历摘要项（某天有几个安排）
struct MonthSummaryItem: Codable, Identifiable {
    var id: String { date }
    let date: String
    let count: Int
}
