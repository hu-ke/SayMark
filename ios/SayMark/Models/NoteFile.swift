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
    let schedule: String? = nil  // 日程属性 JSON 字符串（独立存储）
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, content, type, date, time
        case reminderMinutes = "reminder_minutes"
        case recurrence
        case recurrenceEndDate = "recurrence_end_date"
        case schedule
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
        if let r = recurrence, !r.isEmpty { return true }
        return scheduleRepeatLabel != nil
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

    /// 从 schedule JSON 解析出的重复描述（秒/分钟/小时/天），无则返回 nil
    var scheduleRepeatLabel: String? {
        guard let schedule,
              let data = schedule.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let repeatObj = obj["repeat"] as? [String: Any],
              let enabled = repeatObj["enabled"] as? Bool, enabled,
              let unit = repeatObj["unit"] as? String,
              let value = repeatObj["value"] as? Int else { return nil }
        let unitLabel: String
        switch unit {
        case "seconds": unitLabel = "秒"
        case "minutes": unitLabel = "分钟"
        case "hours": unitLabel = "小时"
        case "days": unitLabel = "天"
        default: unitLabel = unit
        }
        return "每 \(value) \(unitLabel)"
    }

    /// 重复周期显示（优先新 repeat，其次旧 recurrence）
    var repeatText: String? {
        if let s = scheduleRepeatLabel, !s.isEmpty { return s }
        return recurrenceLabel.isEmpty ? nil : recurrenceLabel
    }
}

/// 日程重复规则（新建日程时使用）
struct ScheduleRepeat: Codable {
    var enabled: Bool
    var unit: String  // "seconds" | "minutes" | "hours" | "days"
    var value: Int
}

/// 日程属性（独立于文件普通属性，后端序列化为 JSON 存入 schedule 字段）
struct SchedulePayload: Codable {
    var date: String  // YYYY-MM-DD
    var time: String  // HH:mm
    var repeatRule: ScheduleRepeat

    enum CodingKeys: String, CodingKey {
        case date, time
        case repeatRule = "repeat"
    }
}

/// 日程属性更新请求体（nil 字段不会被发送）
struct ScheduleUpdatePayload: Codable {
    var date: String?
    var time: String?
    var reminder_minutes: Int?
    var recurrence: String?
    var recurrence_end_date: String?
    var repeat_enabled: Bool?
    var repeat_unit: String?
    var repeat_value: Int?
}
