import SwiftUI

struct RemindersView: View {
    @StateObject private var viewModel = RemindersViewModel()
    @State private var showDeleteAlert = false
    @State private var deleteReminderId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Spacer()
                    Text("提醒")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                    Spacer()
                    if !viewModel.reminders.isEmpty {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20))
                                .foregroundColor(UIConstants.blue)
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                if viewModel.loading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if viewModel.reminders.isEmpty {
                    emptyState
                } else {
                    remindersList
                }
            }
            .background(UIConstants.background)
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            // 铃铛插图
            ZStack {
                Circle()
                    .fill(UIConstants.label3.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(UIConstants.label3)
            }

            VStack(spacing: 6) {
                Text("暂无提醒")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.5)
                Text("还没有设置任何日程提醒")
                    .font(.system(size: 15))
                    .foregroundColor(UIConstants.label3)
                    .kerning(-0.24)
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Reminders List
    private var remindersList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(viewModel.reminders) { reminder in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            TabIcon(type: "bell", size: 22, color: UIConstants.orange, strokeWidth: 2)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(UIConstants.label)
                                    .kerning(-0.32)

                                HStack(spacing: 4) {
                                    TabIcon(type: "cal", size: 11, color: UIConstants.label3, strokeWidth: 1.6)
                                    Text(formatReminderTime(reminder))
                                        .font(.system(size: 12))
                                        .foregroundColor(UIConstants.label3)
                                }

                                if reminder.hasReminder, let minutes = reminder.reminderMinutes {
                                    Text("提前\(formatMinutes(minutes))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(UIConstants.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(UIConstants.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                        .padding(.top, 2)
                                }
                            }

                            Spacer()

                            Button {
                                deleteReminderId = reminder.id
                                showDeleteAlert = true
                            } label: {
                                TabIcon(type: "bell-off", size: 18, color: UIConstants.label3, strokeWidth: 1.8)
                                    .padding(4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .background(UIConstants.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Color.clear.frame(height: 20)
        }
        .confirmationDialog("确定删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                if let id = deleteReminderId {
                    Task { await viewModel.deleteReminder(id: id) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除此提醒。")
        }
    }

    // MARK: - Helpers
    private func formatReminderTime(_ reminder: NoteFile) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: reminder.time)
            ?? ISO8601DateFormatter().date(from: reminder.time)
            ?? Date()

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)分钟"
        } else if minutes == 60 {
            return "1小时"
        } else {
            return "\(minutes / 60)小时"
        }
    }
}

// MARK: - Reminders ViewModel
@MainActor
class RemindersViewModel: ObservableObject {
    @Published var reminders: [NoteFile] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let notes = try await APIClient.shared.getReminderNotes()
            reminders = notes
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteReminder(id: String) async {
        do {
            _ = try await APIClient.shared.requestEmpty(
                path: "/api/files/\(id)",
                method: "DELETE"
            )
            reminders.removeAll(where: { $0.id == id })
        } catch {
            print("deleteReminder error:", error)
        }
    }
}
