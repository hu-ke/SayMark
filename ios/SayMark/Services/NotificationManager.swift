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
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("[Notify] requestPermission -> \(granted)")
            return granted
        } catch {
            print("[Notify] requestPermission error: \(error)")
            return false
        }
    }

    private func logAuthStatus() async {
        let settings = await center.notificationSettings()
        print("[Notify] authorizationStatus = \(settings.authorizationStatus.rawValue)")
    }

    /// 根据提醒列表调度所有本地通知
    func scheduleNotifications(from reminders: [NoteFile]) async {
        print("[Notify] scheduleNotifications: \(reminders.count) 条提醒")
        center.removeAllPendingNotificationRequests()

        let formatter = DateFormatter()
        let dateOnlyFmt = DateFormatter()
        dateOnlyFmt.dateFormat = "yyyy-MM-dd"

        for item in reminders {
            guard let minutes = item.reminderMinutes else {
                print("[Notify] 跳过「\(item.name)」：无 reminderMinutes")
                continue
            }
            guard !item.date.isEmpty else {
                print("[Notify] 跳过「\(item.name)」：date 为空")
                continue
            }

            // 后端 time 可能是 "HH:mm:ss"，截取为 "HH:mm" 再解析
            let timeStr = item.time.count >= 5 ? String(item.time.prefix(5)) : item.time
            let dateStr = item.date + (timeStr.isEmpty ? "T00:00" : "T\(timeStr)")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            guard let eventDate = formatter.date(from: dateStr) else {
                print("[Notify] 跳过「\(item.name)」：无法解析 date=\(item.date) time=\(item.time)")
                continue
            }

            let triggerDate = eventDate.addingTimeInterval(-Double(minutes) * 60)
            let body = bodyPreview(from: item)
            let advanceDesc = minutes > 0 ? "提前\(minutes)分钟" : "到点"
            print("[Notify] 「\(item.name)」事件=\(dateStr) \(advanceDesc) 触发=\(triggerDate)")

            var endDate: Date? = nil
            if !item.recurrenceEndDate.isEmpty {
                endDate = dateOnlyFmt.date(from: item.recurrenceEndDate)
            }

            // 优先新格式重复（秒/分钟/小时/天），其次旧 recurrence（每天/每周/每月）
            if let rule = item.scheduleRepeatRule {
                scheduleSeries(id: item.id, title: item.name, body: body, first: triggerDate,
                               step: { self.nextDate(after: $0, rule: rule) }, endDate: endDate)
            } else {
                let rc = item.recurrence ?? ""
                if rc.isEmpty {
                    if triggerDate.timeIntervalSinceNow > 0 {
                        schedule(id: item.id, title: item.name, body: body, at: triggerDate)
                    } else {
                        print("[Notify] 「\(item.name)」触发时间已过，不调度")
                    }
                } else {
                    scheduleSeries(id: item.id, title: item.name, body: body, first: triggerDate,
                                   step: { self.advance($0, by: rc) }, endDate: endDate)
                }
            }
        }

        let pending = await center.pendingNotificationRequests()
        print("[Notify] 调度完成，当前待处理通知数 = \(pending.count)")
        for req in pending {
            if let trig = req.trigger as? UNCalendarNotificationTrigger {
                let d = trig.nextTriggerDate() ?? Date()
                print("[Notify]   已调度: \(req.identifier) → \(d)")
            } else if let trig = req.trigger as? UNTimeIntervalNotificationTrigger {
                print("[Notify]   已调度: \(req.identifier) → interval=\(trig.timeInterval)s")
            }
        }
    }

    /// 从后端拉取最新提醒并重新调度（供创建/编辑/删除日程后调用）
    func refreshFromServer() async {
        let settings = await center.notificationSettings()
        print("[Notify] refreshFromServer authorizationStatus = \(settings.authorizationStatus.rawValue)")
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            print("[Notify] 未授权，停止调度")
            return
        }
        do {
            let notes = try await APIClient.shared.getReminderNotes()
            print("[Notify] getReminderNotes 返回 \(notes.count) 条")
            await scheduleNotifications(from: notes)
        } catch {
            print("[Notify] getReminderNotes 失败: \(error)")
        }
    }

    /// 调度一系列周期性通知：从首次触发开始，按 step 推进，直到结束日期或上限
    private func scheduleSeries(id: String, title: String, body: String, first: Date,
                                step: (Date) -> Date?, endDate: Date?) {
        var cursor = first
        var idx = 0
        let maxCount = 64  // iOS 本地通知待处理上限
        while idx < maxCount {
            if cursor.timeIntervalSinceNow > 0 {
                schedule(id: "\(id)-\(idx)", title: title, body: body, at: cursor)
            }
            guard let next = step(cursor) else { break }
            cursor = next
            if let end = endDate, cal.compare(cursor, to: end, toGranularity: .day) == .orderedDescending {
                break
            }
            idx += 1
        }
    }

    /// 调度单个通知（一次性，精确到分钟）
    private func schedule(id: String, title: String, body: String, at date: Date) {
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

    /// 按周期推进日期（旧 recurrence：每天/每周/每月）
    private func advance(_ date: Date, by recurrence: String) -> Date? {
        switch recurrence {
        case "daily":  return cal.date(byAdding: .day, value: 1, to: date)
        case "weekly": return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date)
        default: return nil
        }
    }

    /// 按新格式重复规则推进日期（秒/分钟/小时/天）
    private func nextDate(after date: Date, rule: ScheduleRepeat) -> Date? {
        switch rule.unit {
        case "seconds": return cal.date(byAdding: .second, value: rule.value, to: date)
        case "minutes": return cal.date(byAdding: .minute, value: rule.value, to: date)
        case "hours": return cal.date(byAdding: .hour, value: rule.value, to: date)
        case "days": return cal.date(byAdding: .day, value: rule.value, to: date)
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
