import SwiftUI

private struct RepeatUnitOption: Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FolderTreeViewModel
    var parentId: String?
    var preSelectedType: String? = nil

    @State private var selectedType: String
    @State private var name: String

    // 文件子类型：普通文件(note) / 日程文件(event)
    @State private var fileKind: String = "note"

    // 日程属性
    @State private var scheduleDate: Date = Date()
    @State private var scheduleTime: Date = Date()
    @State private var repeatEnabled: Bool = false
    @State private var repeatUnit: String = "days"
    @State private var repeatValue: Int = 1

    private let repeatUnits: [RepeatUnitOption] = [
        RepeatUnitOption(value: "seconds", label: "秒"),
        RepeatUnitOption(value: "minutes", label: "分钟"),
        RepeatUnitOption(value: "hours", label: "小时"),
        RepeatUnitOption(value: "days", label: "天"),
    ]

    init(viewModel: FolderTreeViewModel, parentId: String? = nil, preSelectedType: String? = nil) {
        self.viewModel = viewModel
        self.parentId = parentId
        self.preSelectedType = preSelectedType
        let initialType = preSelectedType ?? "folder"
        self._selectedType = State(initialValue: initialType)
        self._name = State(initialValue: initialType == "file" ? "新建文件" : "新建文件夹")
    }

    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                        Text("文件")
                    }
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.blue)
                }

                Spacer()

                Text("新建")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.41)

                Spacer()

                Button("创建") {
                    create()
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(name.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? UIConstants.blue.opacity(0.35)
                                 : UIConstants.blue)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

            ScrollView {
                VStack(spacing: 0) {
                    // 类型选择
                    sectionHeader("类型")
                    VStack(spacing: 0) {
                        typeOption(type: "folder", icon: "folder.fill", label: "文件夹", color: UIConstants.blue)

                        if parentId != nil {
                            Divider().padding(.leading, 56)
                            typeOption(type: "file", icon: "doc.text.fill", label: "文件", color: UIConstants.label3)
                        }
                    }
                    .cardStyle()

                    // 文件子类型
                    if selectedType == "file" {
                        sectionHeader("文件类型", top: 14)
                        VStack(spacing: 0) {
                            fileKindOption(kind: "note", icon: "doc.text.fill", label: "普通文件")
                            Divider().padding(.leading, 56)
                            fileKindOption(kind: "event", icon: "calendar", label: "日程文件")
                        }
                        .cardStyle()
                    }

                    // 日程时间与重复
                    if selectedType == "file" && fileKind == "event" {
                        sectionHeader("日程时间", top: 14)
                        VStack(spacing: 0) {
                            DatePicker("日期", selection: $scheduleDate, displayedComponents: .date)
                                .font(.system(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)

                            Divider().padding(.leading, 16)

                            DatePicker("时间", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                                .font(.system(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                        }
                        .cardStyle()

                        sectionHeader("重复", top: 14)
                        VStack(spacing: 0) {
                            Toggle("重复", isOn: $repeatEnabled)
                                .tint(UIConstants.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)

                            if repeatEnabled {
                                Divider().padding(.leading, 16)

                                HStack {
                                    Text("单位")
                                        .font(.system(size: 16))
                                        .foregroundColor(UIConstants.label)
                                    Spacer()
                                    Picker("单位", selection: $repeatUnit) {
                                        ForEach(repeatUnits, id: \.value) { unit in
                                            Text(unit.label).tag(unit.value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(UIConstants.label3)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)

                                Divider().padding(.leading, 16)

                                HStack {
                                    Text("值")
                                        .font(.system(size: 16))
                                        .foregroundColor(UIConstants.label)
                                    Spacer()
                                    Stepper("\(repeatValue)", value: $repeatValue, in: 1...9999)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                        }
                        .cardStyle()
                    }

                    // 名称输入
                    sectionHeader("名称", top: 14)
                    VStack(spacing: 0) {
                        HStack {
                            TextField("输入名称", text: $name)
                                .font(.system(size: 17))
                                .kerning(-0.41)
                            if !name.isEmpty {
                                Button {
                                    name = ""
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(UIConstants.label3))
                                }
                            }
                        }
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
        .navigationBarHidden(true)
    }

    private func sectionHeader(_ title: String, top: CGFloat = 20) -> some View {
        Text(title)
            .font(.system(size: 13))
            .textCase(.uppercase)
            .foregroundColor(UIConstants.label3)
            .kerning(0.065)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
            .padding(.top, top)
    }

    private func typeOption(type: String, icon: String, label: String, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedType = type
            }
            name = type == "folder" ? "新建文件夹" : "新建文件"
        } label: {
            HStack(spacing: 12) {
                RowIcon(systemName: icon, color: color)
                Text(label)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                Spacer()
                if selectedType == type {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(UIConstants.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileKindOption(kind: String, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                fileKind = kind
            }
        } label: {
            HStack(spacing: 12) {
                RowIcon(systemName: icon, color: kind == "event" ? UIConstants.orange : UIConstants.label3)
                Text(label)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                Spacer()
                if fileKind == kind {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(UIConstants.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pid = parentId ?? ""
        Task {
            if selectedType == "folder" {
                await viewModel.createFolder(name: trimmed, parentId: parentId)
            } else if fileKind == "event" {
                let schedule = SchedulePayload(
                    date: dateString(from: scheduleDate),
                    time: timeString(from: scheduleTime),
                    repeatRule: ScheduleRepeat(enabled: repeatEnabled, unit: repeatUnit, value: repeatValue)
                )
                await viewModel.createFile(name: trimmed, content: "", parentId: pid, type: "event", schedule: schedule)
            } else {
                await viewModel.createFile(name: trimmed, content: "", parentId: pid, type: "note", schedule: nil)
            }
        }
        dismiss()
    }

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
