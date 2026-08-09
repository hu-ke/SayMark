import SwiftUI

/// 提醒列表：显示所有设置了提醒的日程
struct RemindersView: View {
    @StateObject private var viewModel = RemindersViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.loading {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("加载中...")
                            .font(DesignTokens.Font.subheadline)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                } else if viewModel.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("暂无提醒", systemImage: "bell.slash")
                            .font(DesignTokens.Font.title3)
                    } description: {
                        Text("还没有设置任何日程提醒\n创建日程时设置提醒时间即可")
                    }
                } else {
                    List {
                        ForEach(viewModel.reminders) { event in
                            ReminderRow(event: event, onCancel: {
                                Task { await viewModel.cancelReminder(id: event.id) }
                            })
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("提醒")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.reminders.isEmpty {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.loading)
                    }
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }
}

/// 提醒行
private struct ReminderRow: View {
    let event: CalendarEvent
    let onCancel: () -> Void
    @State private var showCancelConfirm = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 图标
            ZStack {
                Circle()
                    .fill(DesignTokens.Color.accentBg)
                    .frame(width: 36, height: 36)
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Color.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(DesignTokens.Font.body)
                    .fontWeight(.medium)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                    Text(event.date)
                        .font(DesignTokens.Font.caption)
                    if !event.time.isEmpty {
                        Text(event.time)
                            .font(DesignTokens.Font.caption)
                    }
                }
                .foregroundStyle(DesignTokens.Color.textSecondary)
            }

            Spacer()

            if let mins = event.reminderMinutes {
                Text("提前\(mins)分钟")
                    .font(DesignTokens.Font.caption2)
                    .foregroundStyle(DesignTokens.Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(DesignTokens.Color.accentBg)
                    .clipShape(Capsule())
            }

            Button {
                showCancelConfirm = true
            } label: {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .confirmationDialog(
            "取消提醒？",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("取消提醒", role: .destructive) { onCancel() }
            Button("保留", role: .cancel) {}
        } message: {
            Text("将取消「\(event.title)」的提醒。")
        }
    }
}

/// 提醒视图模型
@MainActor
final class RemindersViewModel: ObservableObject {
    @Published var reminders: [CalendarEvent] = []
    @Published var loading = false

    private let api = APIClient.shared

    func load() async {
        loading = true
        do {
            reminders = try await api.getReminders()
            if let notes = try? await api.getReminderNotes() {
                await NotificationManager.shared.scheduleNotifications(from: notes)
            }
        } catch {
            reminders = []
        }
        loading = false
    }

    func cancelReminder(id: String) async {
        do {
            try await api.cancelReminder(id: id)
            reminders.removeAll { $0.id == id }
            if let notes = try? await api.getReminderNotes() {
                await NotificationManager.shared.scheduleNotifications(from: notes)
            }
        } catch {}
    }
}
