import SwiftUI

/// Figma 风格的提醒列表：卡片式 + 空态插图 + 徽章样式
struct RemindersView: View {
    @StateObject private var viewModel = RemindersViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.loading {
                    ProgressView("加载中...")
                } else if viewModel.reminders.isEmpty {
                    emptyState
                } else {
                    reminderList
                }
            }
            .navigationTitle("提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.reminders.isEmpty {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17))
                                .foregroundStyle(DesignColor.blue)
                        }
                        .disabled(viewModel.loading)
                    }
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }

    // MARK: - 提醒列表（Figma 卡片式）

    private var reminderList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(viewModel.reminders) { event in
                    ReminderCardView(event: event, onCancel: {
                        Task { await viewModel.cancelReminder(id: event.id) }
                    })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.load() }
    }

    // MARK: - 空状态（Figma 风格）

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            // 铃铛插画
            ZStack {
                Circle()
                    .fill(DesignColor.label3.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "bell.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignColor.label3.opacity(0.4))
                // 斜线表示"已关闭"
                Path { path in
                    path.move(to: CGPoint(x: -18, y: -18))
                    path.addLine(to: CGPoint(x: 18, y: 18))
                }
                .stroke(DesignColor.label3.opacity(0.5), lineWidth: 2)
                .frame(width: 36, height: 36)
            }

            VStack(spacing: 8) {
                Text("暂无提醒")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignColor.label)
                Text("还没有设置任何日程提醒")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignColor.label3)
            }
            .padding(.top, 4)

            Spacer()
        }
    }
}

// MARK: - 提醒卡片

/// Figma 风格的提醒卡片
private struct ReminderCardView: View {
    let event: CalendarEvent
    let onCancel: () -> Void
    @State private var showCancelConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // 铃铛图标
            Image(systemName: "bell.fill")
                .font(.system(size: 18))
                .foregroundStyle(DesignColor.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DesignColor.label)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(event.date)
                            .font(.system(size: 12))
                        if !event.time.isEmpty {
                            Text(event.time)
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundStyle(DesignColor.label3)

                    if let mins = event.reminderMinutes {
                        Text("提前\(mins)分钟")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignColor.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DesignColor.orange.opacity(0.12))
                            )
                    }
                }
            }

            Spacer()

            Button {
                showCancelConfirm = true
            } label: {
                Image(systemName: "bell.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignColor.label3)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(DesignColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - 视图模型（保持不变）

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
