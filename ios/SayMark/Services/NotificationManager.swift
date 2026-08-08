import UserNotifications
import Foundation

/// 通知管理器：请求权限 + 根据提醒数据调度本地通知
/// 支持一次性与周期性（daily/weekly/monthly）通知，支持结束日期
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let cal = Calendar.current

    override private init() {
        super.init()
        center.delegate = self
    }

    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 根据提醒列表调度所有本地通知
    func scheduleNotifications(from reminders: [NoteFile]) async {
        center.removeAllPendingNotificationRequests()

        let formatter = DateFormatter()
        let dateOnlyFmt = DateFormatter()
        dateOnlyFmt.dateFormat = "yyyy-MM-dd"

        for item in reminders {
            guard let minutes = item.reminderMinutes, minutes > 0 else { continue }
            guard !item.date.isEmpty else { continue }

            let dateStr = item.date + (item.time.isEmpty ? "T00:00" : "T\(item.time)")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            guard let eventDate = formatter.date(from: dateStr) else { continue }

            let triggerDate = eventDate.addingTimeInterval(-Double(minutes) * 60)
            let body = bodyPreview(from: item)
            let rc = item.recurrence ?? ""

            // 解析结束日期
            var endDate: Date? = nil
            if !item.recurrenceEndDate.isEmpty {
                endDate = dateOnlyFmt.date(from: item.recurrenceEndDate)
            }

            if rc.isEmpty {
                // 一次性
                if triggerDate.timeIntervalSinceNow > 0 {
                    schedule(id: item.id, title: item.name, body: body, at: triggerDate, rc: nil)
                }
            } else {
                // 周期性：逐个调度，直到结束日期或达到上限
                var cursor = triggerDate
                var idx = 0
                let maxCount = 100  // 安全上限
                while idx < maxCount {
                    if cursor.timeIntervalSinceNow > 0 {
                        schedule(id: "\(item.id)-\(idx)", title: item.name, body: body, at: cursor, rc: nil)
                    }
                    // 计算下一次
                    guard let next = advance(cursor, by: rc) else { break }
                    cursor = next
                    // 检查是否超过结束日期
                    if let end = endDate, cal.compare(cursor, to: end, toGranularity: .day) == .orderedDescending {
                        break
                    }
                    idx += 1
                }
            }
        }
    }

    /// 调度单个通知（一次性，精确到分钟）
    private func schedule(id: String, title: String, body: String, at date: Date, rc _: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["file_id": id]

        // 一次性通知：精确到年月日时分
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "reminder-\(id)", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error { print("通知调度失败: \(error)") }
        }
    }

    /// 按周期推进日期
    private func advance(_ date: Date, by recurrence: String) -> Date? {
        switch recurrence {
        case "daily":  return cal.date(byAdding: .day, value: 1, to: date)
        case "weekly": return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date)
        default: return nil
        }
    }

    /// 生成通知正文预览
    private func bodyPreview(from item: NoteFile) -> String {
        let content = item.content ?? ""
        if content.isEmpty { return "提醒时间到了" }
        let lines = content.split(separator: "\n").map(String.init)
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let preview = meaningful.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return preview.isEmpty ? "提醒时间到了" : String(preview.prefix(100))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
