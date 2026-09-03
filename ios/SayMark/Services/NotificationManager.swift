import UserNotifications
import Foundation

/// 通知管理器：请求权限 + 根据安排/闹钟调度本地通知
/// 安排（appointment）到点推送一次；闹钟（alarm）按周期重复推送。
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
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("[Notify] requestPermission -> \(granted)")
            return granted
        } catch {
            print("[Notify] requestPermission error: \(error)")
            return false
        }
    }

    /// 根据安排 + 闹钟调度所有本地通知
    func scheduleNotifications(appointments: [Appointment], alarms: [Alarm]) async {
        print("[Notify] scheduleNotifications: \(appointments.count) 条安排, \(alarms.count) 个闹钟")
        center.removeAllPendingNotificationRequests()

        for item in appointments {
            scheduleAppointment(item)
        }
        for item in alarms {
            scheduleAlarm(item)
        }

        let pending = await center.pendingNotificationRequests()
        print("[Notify] 调度完成，当前待处理通知数 = \(pending.count)")
    }

    /// 从后端拉取最新安排与闹钟并重新调度
    func refreshFromServer() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            print("[Notify] 未授权，停止调度")
            return
        }
        do {
            async let appointments = APIClient.shared.getAppointments()
            async let alarms = APIClient.shared.getAlarms()
            await scheduleNotifications(appointments: try await appointments, alarms: try await alarms)
        } catch {
            print("[Notify] refreshFromServer 失败: \(error)")
        }
    }

    // MARK: - 安排（一次性）

    private func scheduleAppointment(_ item: Appointment) {
        guard !item.date.isEmpty else { return }
        let timeStr = item.timeDisplay
        let dateStr = item.date + (timeStr.isEmpty ? "T09:00" : "T\(timeStr)")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = formatter.date(from: dateStr) else {
            print("[Notify] 跳过「\(item.name)」：无法解析 date=\(item.date) time=\(item.time)")
            return
        }
        guard date.timeIntervalSinceNow > 0 else {
            print("[Notify] 「\(item.name)」时间已过，不调度")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = item.name
        content.body = bodyPreview(content: item.content)
        content.sound = .default
        content.userInfo = ["type": "appointment", "file_id": item.id]

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: "appointment-\(item.id)", content: content, trigger: trigger)) { error in
            if let error = error { print("通知调度失败: \(error)") }
        }
    }

    // MARK: - 闹钟（周期性）

    private func scheduleAlarm(_ item: Alarm) {
        let timeStr = item.timeDisplay
        guard !timeStr.isEmpty, let (hour, minute) = parseTime(timeStr) else {
            print("[Notify] 跳过「\(item.name)」：无法解析 time=\(item.time)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = item.name
        content.body = bodyPreview(content: item.content)
        content.sound = .default
        content.userInfo = ["type": "alarm", "file_id": item.id]

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        // weekly/monthly 需要一个锚点日/星期几（取闹钟创建当天）
        if item.recurrence == "weekly" {
            components.weekday = cal.component(.weekday, from: createdDate(item) ?? Date())
        } else if item.recurrence == "monthly" {
            components.day = cal.component(.day, from: createdDate(item) ?? Date())
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "alarm-\(item.id)", content: content, trigger: trigger)) { error in
            if let error = error { print("通知调度失败: \(error)") }
        }
    }

    private func parseTime(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }

    private func createdDate(_ item: Alarm) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: item.createdAt) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: item.createdAt)
    }

    private func bodyPreview(content: String) -> String {
        if content.isEmpty { return "时间到了" }
        let lines = content.split(separator: "\n").map(String.init)
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let preview = meaningful.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return preview.isEmpty ? "时间到了" : String(preview.prefix(100))
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
