import SwiftUI

struct CalendarView: View {
    @ObservedObject var treeViewModel: FolderTreeViewModel
    @StateObject private var viewModel = AppointmentViewModel()

    @State private var selectedDay: Int?
    @State private var currentMonth: Date = Calendar.current.startOfMonth(for: Date()) ?? Date()
    @State private var showDeleteAlert = false
    @State private var deleteAppointmentId: String?
    @State private var deleteAppointmentTitle: String?

    // MARK: - Weekday labels
    private let weekDays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导航栏
                HStack {
                    Spacer()
                    Text("日历")
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)
                    Spacer()
                }
                .frame(height: 44)
                .background(
                    UIConstants.background.opacity(0.82)
                        .background(Material.ultraThin)
                )
                .overlay(alignment: .bottom) {
                    HDSeparator()
                }

                // 月份选择器
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                        }
                        selectedDay = nil
                        Task { await loadMonth() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                    }

                    Spacer()

                    Text(monthYearString(from: currentMonth))
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                        }
                        selectedDay = nil
                        Task { await loadMonth() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                // 日历网格
                VStack(spacing: 0) {
                    // 星期头
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            Text(day)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(UIConstants.label3)
                                .frame(height: 24)
                        }
                    }
                    .padding(.horizontal, 12)

                    // 日期网格
                    let days = generateDays(for: currentMonth)
                    ForEach(0..<days.count / 7, id: \.self) { week in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                let i = week * 7 + dayIndex
                                if i < days.count, let day = days[i] {
                                    calendarDayCell(day: day)
                                } else {
                                    Color.clear.frame(height: 44)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 4)
                .background(UIConstants.card)

                // 分隔线
                HDSeparator()

                // 安排列表
                if let day = selectedDay, !viewModel.dayAppointments.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("\(Calendar.current.component(.month, from: currentMonth))月\(day)日")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(UIConstants.label)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)

                            VStack(spacing: 10) {
                                ForEach(viewModel.dayAppointments) { appointment in
                                    appointmentRow(appointment: appointment)
                                }
                            }
                            .padding(.horizontal, 16)

                            Color.clear.frame(height: 20)
                        }
                    }
                    .background(UIConstants.background)
                } else if selectedDay != nil && viewModel.dayAppointments.isEmpty {
                    VStack {
                        Spacer()
                        Text("暂无安排")
                            .font(.system(size: 15))
                            .foregroundColor(UIConstants.label3)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(UIConstants.background)
                } else {
                    Color(UIConstants.background)
                }
            }
            .background(UIConstants.background)
        }
        .task {
            await loadMonth()
        }
        .confirmationDialog("确定删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                if let id = deleteAppointmentId {
                    Task { await viewModel.deleteAppointment(id: id) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let title = deleteAppointmentTitle {
                Text("将删除安排「\(title)」。")
            }
        }
    }

    // MARK: - Calendar Day Cell
    private func calendarDayCell(day: Int) -> some View {
        let dayDate = Calendar.current.date(bySetting: .day, value: day, of: currentMonth) ?? Date()
        let today = Calendar.current.isDateInToday(dayDate)
        let isPast = !today && dayDate < Calendar.current.startOfDay(for: Date())
        let isSelected = day == selectedDay
        let hasAppointment = viewModel.appointmentDays.contains(day)

        return VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        selectedDay = nil
                    } else {
                        selectedDay = day
                    }
                }
                Task {
                    await loadDay(day)
                }
            } label: {
                Text("\(day)")
                    .font(.system(size: 14, weight: today ? .bold : .regular))
                    .foregroundColor(isSelected ? .white
                                     : today ? UIConstants.blue
                                     : isPast ? UIConstants.label3
                                     : UIConstants.label)
                    .frame(width: 32, height: 32)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(UIConstants.blue)
                            } else if today {
                                Circle()
                                    .stroke(UIConstants.blue, lineWidth: 2)
                            }
                        }
                    )
            }

            if hasAppointment && !isSelected {
                Circle()
                    .fill(UIConstants.orange)
                    .frame(width: 5, height: 5)
            } else {
                Color.clear.frame(width: 5, height: 5)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Appointment Row
    private func appointmentRow(appointment: Appointment) -> some View {
        NavigationLink {
            FileDetailView(fileId: appointment.id, fileName: appointment.name, folderTreeViewModel: treeViewModel)
        } label: {
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
                    if !appointment.content.isEmpty {
                        Text(appointment.content)
                            .font(.system(size: 13))
                            .foregroundColor(UIConstants.label3)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(UIConstants.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteAppointmentId = appointment.id
                deleteAppointmentTitle = appointment.name
                showDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Data Loading
    private func loadMonth() async {
        let cal = Calendar.current
        let year = cal.component(.year, from: currentMonth)
        let month = cal.component(.month, from: currentMonth)
        await viewModel.loadMonth(year: year, month: month)
    }

    private func loadDay(_ day: Int) async {
        let cal = Calendar.current
        let year = cal.component(.year, from: currentMonth)
        let month = cal.component(.month, from: currentMonth)
        await viewModel.loadDay(year: year, month: month, day: day)
    }

    // MARK: - Helpers
    private func monthYearString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private func generateDays(for date: Date) -> [Int?] {
        let cal = Calendar.current
        guard let firstDay = cal.startOfMonth(for: date) else { return [] }

        let range = cal.range(of: .day, in: .month, for: date) ?? (1..<31)
        let weekday = cal.component(.weekday, from: firstDay) // 1=Sun, 2=Mon...
        var offset = weekday - 2 // 转为周一起始
        if offset < 0 { offset += 7 }

        var result: [Int?] = Array(repeating: nil, count: offset)
        result += range.map { $0 as Int? }

        while result.count % 7 != 0 {
            result.append(nil)
        }

        return result
    }
}

// MARK: - Calendar Start of Month Extension
extension Calendar {
    func startOfMonth(for date: Date) -> Date? {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)
    }
}

// MARK: - Appointment ViewModel
@MainActor
class AppointmentViewModel: ObservableObject {
    @Published var appointmentDays: Set<Int> = []
    @Published var dayAppointments: [Appointment] = []

    func loadMonth(year: Int, month: Int) async {
        do {
            let summary: [MonthSummaryItem] = try await APIClient.shared.getMonthSummary(year: year, month: month)
            appointmentDays = Set(summary.compactMap {
                Calendar.current.dateComponents([.day], from: isoToDate($0.date)).day
            })
        } catch {
            print("loadMonth error:", error)
        }
    }

    func loadDay(year: Int, month: Int, day: Int) async {
        do {
            let dateStr = String(format: "%04d-%02d-%02d", year, month, day)
            let appointments: [Appointment] = try await APIClient.shared.getAppointmentsByDate(dateStr)
            dayAppointments = appointments
        } catch {
            print("loadDay error:", error)
            dayAppointments = []
        }
    }

    func deleteAppointment(id: String) async {
        do {
            try await APIClient.shared.deleteAppointment(id: id)
            dayAppointments.removeAll(where: { $0.id == id })
            await NotificationManager.shared.refreshFromServer()
        } catch {
            print("deleteAppointment error:", error)
        }
    }

    private func isoToDate(_ str: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: str) ?? Date()
    }
}
