import SwiftUI

/// 安排列表（一次性日程）
struct AppointmentsView: View {
    @ObservedObject var treeViewModel: FolderTreeViewModel
    @StateObject private var viewModel = AppointmentListViewModel()
    @State private var showCreate = false
    @State private var showDeleteAlert = false
    @State private var deleteAppointmentId: String?
    @State private var deleteAppointmentName: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Spacer()
                    Text("安排")
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

                if viewModel.loading && viewModel.appointments.isEmpty {
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Spacer()
                } else if viewModel.appointments.isEmpty {
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
            NewAppointmentSheet {
                Task { await viewModel.load() }
            }
        }
        .confirmationDialog("确定删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                if let id = deleteAppointmentId {
                    Task { await viewModel.deleteAppointment(id: id) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let name = deleteAppointmentName {
                Text("将删除安排「\(name)」。")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(UIConstants.label3.opacity(0.6))
            VStack(spacing: 6) {
                Text("暂无安排")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.5)
                Text("点击右上角 + 新建一次性安排")
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
                ForEach(viewModel.appointments) { appointment in
                    HStack(spacing: 0) {
                        NavigationLink {
                            FileDetailView(fileId: appointment.id, fileName: appointment.name, folderTreeViewModel: treeViewModel)
                        } label: {
                            appointmentCard(appointment)
                        }
                        .buttonStyle(.plain)

                        Button {
                            deleteAppointmentId = appointment.id
                            deleteAppointmentName = appointment.name
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

    private func appointmentCard(_ appointment: Appointment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(UIConstants.blue)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(appointment.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(UIConstants.label)
                        .kerning(-0.32)
                    Spacer()
                    if !appointment.time.isEmpty {
                        Text(appointment.timeDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                    }
                }
                Text(appointment.date)
                    .font(.system(size: 12))
                    .foregroundColor(UIConstants.label3)
            }
        }
        .padding(.vertical, 13)
        .padding(.leading, 16)
        .padding(.trailing, 8)
    }
}

// MARK: - 新建安排 Sheet

struct NewAppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void

    @State private var name = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.blue)
                Spacer()
                Text("新建安排")
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
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        Divider().padding(.leading, 16)
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                            .font(.system(size: 16))
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
        let dateStr = format(date, "yyyy-MM-dd")
        let timeStr = format(time, "HH:mm")
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await APIClient.shared.createAppointment(name: trimmed, date: dateStr, time: timeStr, content: "")
                await NotificationManager.shared.refreshFromServer()
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func format(_ d: Date, _ fmt: String) -> String {
        let f = DateFormatter()
        f.dateFormat = fmt
        return f.string(from: d)
    }
}

// MARK: - 安排列表 ViewModel

@MainActor
class AppointmentListViewModel: ObservableObject {
    @Published var appointments: [Appointment] = []
    @Published var loading = false

    func load() async {
        loading = true
        defer { loading = false }
        do {
            appointments = try await APIClient.shared.getAppointments()
        } catch {
            print("load appointments error:", error)
        }
    }

    func deleteAppointment(id: String) async {
        do {
            try await APIClient.shared.deleteAppointment(id: id)
            appointments.removeAll(where: { $0.id == id })
            await NotificationManager.shared.refreshFromServer()
        } catch {
            print("deleteAppointment error:", error)
        }
    }
}
