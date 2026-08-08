import SwiftUI

/// 日历视图：月历 + 选中日的日程列表
struct CalendarView: View {
    @StateObject private var viewModel = CalendarEventViewModel()
    @ObservedObject var treeViewModel: FolderTreeViewModel

    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()

    private let calendar = Calendar.current

    /// 当前月份的日期（含前后填充）
    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1       // 0=Sun..6=Sat
        let offset = (firstWeekday + 6) % 7  // 转为周一开头：0=Mon..6=Sun
        let totalSlots = offset + range.count
        let paddedTo = Int(ceil(Double(totalSlots) / 7.0)) * 7

        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        while days.count < paddedTo {
            days.append(nil)
        }
        return days
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月份切换
                monthHeader
                // 星期头
                weekdayHeader
                // 日期网格
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                        if let date = date {
                            dayCell(for: date)
                        } else {
                            Color.clear
                                .frame(height: 36)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()

                // 选中日的日程列表
                eventList
            }
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: currentMonth) {
                await viewModel.loadMonth(year: year(from: currentMonth), month: month(from: currentMonth))
            }
            .task(id: selectedDate) {
                await viewModel.loadDay(dateString(from: selectedDate))
            }
        }
    }

    // MARK: - 子视图

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)! }
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthFormatter.string(from: currentMonth))
                .font(.headline)
            Spacer()
            Button {
                withAnimation { currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)! }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var weekdayHeader: some View {
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        return HStack {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func dayCell(for date: Date) -> some View {
        let dateStr = dateString(from: date)
        let hasEvents = viewModel.eventDates.contains(dateStr)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(
                        isSelected ? .white
                        : isToday ? .accentColor
                        : isCurrentMonth ? .primary
                        : .secondary
                    )
                if hasEvents {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private var eventList: some View {
        Group {
            if viewModel.loadingDay {
                ProgressView()
                    .padding(.top, 40)
            } else if viewModel.dayEvents.isEmpty {
                VStack(spacing: 8) {
                    Text("\(month(from: selectedDate))月\(calendar.component(.day, from: selectedDate))日")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("当天无日程")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            } else {
                List {
                    ForEach(viewModel.dayEvents) { event in
                        EventRow(event: event, onDelete: {
                            Task {
                                await viewModel.deleteEvent(id: event.id)
                                await viewModel.loadMonth(year: year(from: currentMonth), month: month(from: currentMonth))
                                await viewModel.loadDay(dateString(from: selectedDate))
                            }
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 工具

    private func year(from date: Date) -> Int {
        calendar.component(.year, from: date)
    }
    private func month(from date: Date) -> Int {
        calendar.component(.month, from: date)
    }
    private func dateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
    private var monthFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月"
        return fmt
    }
}

/// 日历视图模型
@MainActor
final class CalendarEventViewModel: ObservableObject {
    @Published var dayEvents: [CalendarEvent] = []
    @Published var eventDates: Set<String> = []
    @Published var loadingDay = false

    private let api = APIClient.shared

    func loadMonth(year: Int, month: Int) async {
        do {
            let items = try await api.getMonthSummary(year: year, month: month)
            eventDates = Set(items.map { $0.date })
        } catch {
            // 静默失败
        }
    }

    func loadDay(_ date: String) async {
        loadingDay = true
        do {
            dayEvents = try await api.getEventsByDate(date)
        } catch {
            dayEvents = []
        }
        loadingDay = false
    }

    func deleteEvent(id: String) async {
        do {
            try await api.deleteEvent(id: id)
        } catch {
            // 静默失败
        }
    }
}

/// 日程行（带滑动手势删除 + 确认弹框）
private struct EventRow: View {
    let event: CalendarEvent
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body)
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if !event.time.isEmpty {
                Text(event.time)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "确定删除日程？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除日程「\(event.title)」。")
        }
    }
}
