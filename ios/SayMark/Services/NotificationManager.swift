import UserNotifications
import Foundation

/// 通知管理器：请求权限 + 根据提醒数据调度本地通知
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    override private init() {
        super.init()
        center.delegate = self
    }

    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// 根据提醒列表调度所有本地通知
    func scheduleNotifications(from reminders: [NoteFile]) async {
        // 先移除所有旧通知
        center.removeAllPendingNotificationRequests()

        for item in reminders {
            guard let minutes = item.reminderMinutes, minutes > 0 else { continue }
            guard !item.date.isEmpty else { continue }

            let dateStr = item.date + (item.time.isEmpty ? "" : "T\(item.time)")

            // 解析日期时间
            let formatter = DateFormatter()
            formatter.dateFormat = item.time.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
            guard let eventDate = formatter.date(from: dateStr) else { continue }

            // 计算通知触发时间（事件时间 - 提前分钟数）
            let triggerDate = eventDate.addingTimeInterval(-Double(minutes) * 60)

            // 如果触发时间已过，跳过（周期性的需要特殊处理）
            if triggerDate.timeIntervalSinceNow <= 0 {
                if item.isRecurring {
                    // 周期性的：计算下一次触发时间
                    guard let nextDate = nextRecurringDate(from: eventDate, recurrence: item.recurrence ?? "") else {
                        continue
                    }
                    await scheduleOne(id: item.id, title: item.name, body: bodyPreview(from: item), at: nextDate, recurrence: item.recurrence)
                }
                continue
            }

            await scheduleOne(id: item.id, title: item.name, body: bodyPreview(from: item), at: triggerDate, recurrence: item.recurrence)
        }
    }

    /// 调度单个通知
    private func scheduleOne(id: String, title: String, body: String, at date: Date, recurrence: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["file_id": id]

        let components: Set<Calendar.Component>
        if let rc = recurrence, !rc.isEmpty {
            // 周期性：只取时分（每天/每周/每月重复）
            components = [.hour, .minute]
        } else {
            // 一次性：精确到秒
            components = [.year, .month, .day, .hour, .minute]
        }

        let dateComponents = Calendar.current.dateComponents(components, from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: recurrence != nil && !recurrence!.isEmpty)
        let request = UNNotificationRequest(identifier: "reminder-\(id)", content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("通知调度失败: \(error)")
        }
    }

    /// 计算周期性提醒的下一次触发时间
    private func nextRecurringDate(from baseDate: Date, recurrence: String) -> Date? {
        let cal = Calendar.current
        var next = baseDate
        switch recurrence {
        case "daily":
            next = cal.date(byAdding: .day, value: 1, to: next) ?? next
        case "weekly":
            next = cal.date(byAdding: .weekOfYear, value: 1, to: next) ?? next
        case "monthly":
            next = cal.date(byAdding: .month, value: 1, to: next) ?? next
        default:
            return nil
        }
        // 确保在将来
        while next.timeIntervalSinceNow <= 0 {
            switch recurrence {
            case "daily": next = cal.date(byAdding: .day, value: 1, to: next) ?? next
            case "weekly": next = cal.date(byAdding: .weekOfYear, value: 1, to: next) ?? next
            case "monthly": next = cal.date(byAdding: .month, value: 1, to: next) ?? next
            default: return nil
            }
        }
        return next
    }

    /// 生成通知正文预览
    private func bodyPreview(from item: NoteFile) -> String {
        let content = item.content ?? ""
        if content.isEmpty { return "提醒时间到了" }
        // 取第一行非标题的文字（跳过 # 开头）
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
        // App 在前台时也显示通知
        completionHandler([.banner, .sound])
    }
}
