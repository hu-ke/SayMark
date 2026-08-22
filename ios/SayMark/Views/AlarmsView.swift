import SwiftUI

/// 闹钟列表（周期性提醒）
struct AlarmsView: View {
    @ObservedObject var treeViewModel: FolderTreeViewModel
    @StateObject private var viewModel = AlarmsViewModel()
    @State private var showCreate = false
    @State private var showDeleteAlert = false
    @State private var deleteAlarmId: String?
    @State private var deleteAlarmName: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Spacer()
                    Text("闹钟")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                    Spacer()
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) { HDSeparator() }

                if viewModel.loading && viewModel.alarms.isEmpty {
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Spacer()
                } else if viewModel.alarms.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(UIConstants.background)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showCreate) {
            NewAlarmSheet {
                Task { await viewModel.load() }
            }
        }
        .confirmationDialog("确定删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                if let id = deleteAlarmId {
                    Task { await viewModel.deleteAlarm(id: id) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let name = deleteAlarmName {
                Text("将删除闹钟「\(name)」。")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "alarm")
                .font(.system(size: 36))
                .foregroundColor(UIConstants.label3.opacity(0.6))
            VStack(spacing: 6) {
                Text("暂无闹钟")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.5)
                Text("点击右上角 + 新建周期性提醒")
                    .font(.system(size: 15))
                    .foregroundColor(UIConstants.label3)
                    .kerning(-0.24)
            }
            .padding(.top, 4)
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(viewModel.alarms) { alarm in
                    HStack(spacing: 0) {
                        NavigationLink {
                            FileDetailView(fileId: alarm.id, fileName: alarm.name, folderTreeViewModel: treeViewModel)
                        } label: {
                            alarmCard(alarm)
                        }
                        .buttonStyle(.plain)

                        Button {
                            deleteAlarmId = alarm.id
                            deleteAlarmName = alarm.name
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundColor(UIConstants.red)
                                .frame(width: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(UIConstants.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Color.clear.frame(height: 20)
        }
    }

    private func alarmCard(_ alarm: Alarm) -> some View {
        HStack(spacing: 12) {
            TabIcon(type: "bell", size: 22, color: UIConstants.orange, strokeWidth: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.32)

                HStack(spacing: 6) {
                    Text(alarm.timeDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(UIConstants.blue)
                    CapsuleBadge(text: alarm.recurrenceLabel, color: UIConstants.orange.opacity(0.14), foregroundColor: UIConstants.orange)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(UIConstants.label3)
        }
        .padding(.vertical, 13)
        .padding(.leading, 16)
        .padding(.trailing, 8)
    }
}

// MARK: - 新建闹钟 Sheet

struct NewAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void

    @State private var name = ""
    @State private var time = Date()
    @State private var recurrence = "daily"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let recurrences: [(String, String)] = [
        ("daily", "每天"),
        ("weekly", "每周"),
        ("monthly", "每月"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.blue)
                Spacer()
                Text("新建闹钟")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.41)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(UIConstants.blue)
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(
                UIConstants.background.opacity(0.82)
                    .background(Material.ultraThin)
            )
            .overlay(alignment: .bottom) { HDSeparator() }

            ScrollView {
                VStack(spacing: 0) {
                    sectionHeader("名称")
                    VStack(spacing: 0) {
                        TextField("输入名称", text: $name)
                            .font(.system(size: 17))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                    }
                    .cardStyle()

                    sectionHeader("时间")
                    VStack(spacing: 0) {
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                    }
                    .cardStyle()

                    sectionHeader("周期")
                    VStack(spacing: 0) {
                        Picker("周期", selection: $recurrence) {
                            ForEach(recurrences, id: \.0) { item in
                                Text(item.1).tag(item.0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    .cardStyle()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(UIConstants.background)
        .alert("保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .textCase(.uppercase)
            .foregroundColor(UIConstants.label3)
            .kerning(0.065)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
            .padding(.top, 20)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let timeStr = f.string(from: time)
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await APIClient.shared.createAlarm(name: trimmed, time: timeStr, recurrence: recurrence, content: "")
                await NotificationManager.shared.refreshFromServer()
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 闹钟列表 ViewModel

@MainActor
class AlarmsViewModel: ObservableObject {
    @Published var alarms: [Alarm] = []
    @Published var loading = false

    func load() async {
        loading = true
        defer { loading = false }
        do {
            alarms = try await APIClient.shared.getAlarms()
        } catch {
            print("load alarms error:", error)
        }
    }

    func deleteAlarm(id: String) async {
        do {
            try await APIClient.shared.deleteAlarm(id: id)
            alarms.removeAll(where: { $0.id == id })
            await NotificationManager.shared.refreshFromServer()
        } catch {
            print("deleteAlarm error:", error)
        }
    }
}
