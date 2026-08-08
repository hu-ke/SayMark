import SwiftUI

/// 提醒列表：显示所有设置了提醒的日程
struct RemindersView: View {
    @StateObject private var viewModel = RemindersViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.loading {
                    ProgressView("加载中...")
                } else if viewModel.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("暂无提醒", systemImage: "bell.slash")
                    } description: {
                        Text("还没有设置任何日程提醒")
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
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // 日期时间
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(event.date)
                            .font(.caption)
                        if !event.time.isEmpty {
                            Text(event.time)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)

                    // 提前多少分钟
                    if let mins = event.reminderMinutes {
                        Text("提前\(mins)分钟")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button {
                showCancelConfirm = true
            } label: {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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
        } catch {
            reminders = []
        }
        loading = false
    }

    func cancelReminder(id: String) async {
        do {
            try await api.cancelReminder(id: id)
            reminders.removeAll { $0.id == id }
        } catch {}
    }
}
