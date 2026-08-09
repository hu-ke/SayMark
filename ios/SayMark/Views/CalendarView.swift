import SwiftUI

/// 日历视图：月历 + 选中日的日程列表
struct CalendarView: View {
    @StateObject private var viewModel = CalendarEventViewModel()
    @ObservedObject var treeViewModel: FolderTreeViewModel

    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()

    private let calendar = Calendar.current

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
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                dateGrid

                Divider()
                    .padding(.top, DesignTokens.Spacing.sm)

                eventListSection
            }
            .background(DesignTokens.Color.bgGrouped)
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

    // MARK: - Subviews

    private var monthHeader: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .padding(DesignTokens.Spacing.sm)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(DesignTokens.Font.title3)
                    .foregroundStyle(DesignTokens.Color.textPrimary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .padding(DesignTokens.Spacing.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Color.bgBase)
    }

    private var weekdayHeader: some View {
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        return HStack(spacing: 0) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(DesignTokens.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(index >= 5 ? DesignTokens.Color.accent : DesignTokens.Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Color.bgBase)
    }

    private var dateGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    dayCell(for: date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Color.bgBase)
    }

    private func dayCell(for date: Date) -> some View {
        let dateStr = dateString(from: date)
        let hasEvents = viewModel.eventDates.contains(dateStr)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: isToday ? .bold : isSelected ? .semibold : .regular, design: .rounded))
                    .frame(width: 32, height: 32)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(DesignTokens.Color.primary)
                            } else if isToday {
                                Circle().stroke(DesignTokens.Color.primary, lineWidth: 2)
                            } else {
                                Circle().fill(Color.clear)
                            }
                        }
                    )
                    .foregroundStyle(
                        isSelected ? .white
                        : isToday ? DesignTokens.Color.primary
                        : isCurrentMonth ? DesignTokens.Color.textPrimary
                        : DesignTokens.Color.textTertiary
                    )

                if hasEvents {
                    Circle()
                        .fill(DesignTokens.Color.accent)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(height: 48)
        }
        .buttonStyle(.plain)
    }

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日期标题
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayFormatter.string(from: selectedDate))
                        .font(DesignTokens.Font.headline)
                    if calendar.isDateInToday(selectedDate) {
                        Text("今天")
                            .font(DesignTokens.Font.caption)
                            .foregroundStyle(DesignTokens.Color.accent)
                            .badgeStyle(DesignTokens.Color.accent)
                    }
                }
                Spacer()
                if !viewModel.dayEvents.isEmpty {
                    Text("\(viewModel.dayEvents.count)个日程")
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            if viewModel.loadingDay {
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                    Text("加载日程...")
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if viewModel.dayEvents.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                    Text("当天无日程")
                        .font(DesignTokens.Font.subheadline)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                    Text("在文件页面录音或输入即可创建日程")
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                List {
                    ForEach(viewModel.dayEvents) { event in
                        NavigationLink(value: event.toNoteFile()) {
                            EventRow(event: event, onDelete: {
                                Task {
                                    await viewModel.deleteEvent(id: event.id)
                                    await viewModel.loadMonth(year: year(from: currentMonth), month: month(from: currentMonth))
                                    await viewModel.loadDay(dateString(from: selectedDate))
                                }
                            })
                        }
                    }
                }
                .listStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .background(DesignTokens.Color.bgBase)
    }

    // MARK: - Helpers

    private func year(from date: Date) -> Int { calendar.component(.year, from: date) }
    private func month(from date: Date) -> Int { calendar.component(.month, from: date) }
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
    private var dayFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日 EEEE"
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt
    }
}

// MARK: - ViewModel

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
        } catch {}
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
        } catch {}
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: CalendarEvent
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 时间指示
            VStack(spacing: 2) {
                if !event.time.isEmpty {
                    Text(event.time)
                        .font(DesignTokens.Font.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.Color.primary)
                        .monospacedDigit()
                } else {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                }
            }
            .frame(width: 48, alignment: .leading)

            // 内容
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(DesignTokens.Font.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(DesignTokens.Font.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Color.textTertiary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
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
