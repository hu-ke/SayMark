import SwiftUI

/// Figma 风格的日历视图：白色卡片日历 + 蓝色指示条事件列表
struct CalendarView: View {
    @StateObject private var viewModel = CalendarEventViewModel()
    @ObservedObject var treeViewModel: FolderTreeViewModel

    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1
        let offset = (firstWeekday + 6) % 7
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
            ScrollView {
                VStack(spacing: 0) {
                    // 日历卡片（白色背景）
                    VStack(spacing: 0) {
                        monthHeader
                        weekdayHeader
                        dateGrid
                    }
                    .padding(.bottom, 8)
                    .background(DesignColor.card)

                    // 分割线
                    Rectangle()
                        .fill(DesignColor.separator)
                        .frame(height: 0.5)

                    // 事件列表
                    eventListSection
                }
            }
            .scrollIndicators(.hidden)
            .background(DesignColor.background)
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NoteFile.self) { file in
                FileDetailView(note: file, viewModel: treeViewModel)
            }
            .task(id: currentMonth) {
                await viewModel.loadMonth(year: year(from: currentMonth), month: month(from: currentMonth))
            }
            .task(id: selectedDate) {
                await viewModel.loadDay(dateString(from: selectedDate))
            }
        }
    }

    // MARK: - 月份切换

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)! }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17))
                    .foregroundStyle(DesignColor.blue)
            }
            Spacer()
            Text(monthFormatter.string(from: currentMonth))
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
                withAnimation { currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)! }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17))
                    .foregroundStyle(DesignColor.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 星期标题

    private var weekdayHeader: some View {
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignColor.label3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - 日期网格

    private var dateGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<daysInMonth.count / 7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let index = row * 7 + col
                        if index < daysInMonth.count, let date = daysInMonth[index] {
                            dayCell(for: date)
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 4)
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
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? DesignColor.blue : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .stroke(isToday && !isSelected ? DesignColor.blue : Color.clear, lineWidth: 2)
                    )
                    .foregroundStyle(
                        isSelected ? .white
                        : isToday ? DesignColor.blue
                        : isCurrentMonth ? DesignColor.label
                        : DesignColor.label3
                    )
                if hasEvents {
                    Circle()
                        .fill(DesignColor.orange)
                        .frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 事件列表

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日期标题
            HStack {
                Text("\(month(from: selectedDate))月\(calendar.component(.day, from: selectedDate))日")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignColor.label)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if viewModel.loadingDay {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if viewModel.dayEvents.isEmpty {
                Text("当天无日程")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignColor.label3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
            } else {
                // 卡片式事件列表
                VStack(spacing: 10) {
                    ForEach(viewModel.dayEvents) { event in
                        NavigationLink(value: event.toNoteFile()) {
                            eventRow(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 12) {
            // 左侧蓝色指示条
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignColor.blue)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DesignColor.label)
                    Spacer()
                    if !event.time.isEmpty {
                        Text(event.time)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignColor.blue)
                    }
                }
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignColor.label3)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(DesignColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - 视图模型（保持不变）

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
