import SwiftUI

struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FolderTreeViewModel
    var parentId: String?
    var preSelectedType: String? = nil

    @State private var selectedType: String
    @State private var name: String
    @State private var fileSubType = "note"       // "note" 或 "event"
    @State private var isRepeating = false
    @State private var repeatValue = 1
    @State private var repeatUnit = "days"       // seconds / minutes / hours / days

    private let repeatUnits: [(String, String)] = [
        ("seconds", "秒"),
        ("minutes", "分钟"),
        ("hours",   "小时"),
        ("days",    "天"),
    ]

    init(viewModel: FolderTreeViewModel, parentId: String? = nil, preSelectedType: String? = nil) {
        self.viewModel = viewModel
        self.parentId = parentId
        self.preSelectedType = preSelectedType
        let type = preSelectedType ?? "folder"
        self._selectedType = State(initialValue: type)
        self._name = State(initialValue: type == "file" ? "新建笔记" : "新文件夹")
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
                    typeSection

                    // 名称输入
                    nameSection

                    // 文件子类型（仅当选中"笔记"时显示）
                    if selectedType == "file" {
                        fileSubTypeSection

                        // 日程文件配置
                        if fileSubType == "event" {
                            repeatSection
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .background(UIConstants.background)
        .navigationBarHidden(true)
        .onChange(of: selectedType) { newType in
            if name == "新文件夹" || name == "新建笔记" {
                name = newType == "file" ? "新建笔记" : "新文件夹"
            }
        }
    }

    // MARK: - 类型选择
    private var typeSection: some View {
        VStack(spacing: 0) {
            Text("类型")
                .font(.system(size: 13))
                .textCase(.uppercase)
                .foregroundColor(UIConstants.label3)
                .kerning(0.065)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
                .padding(.top, 20)

            VStack(spacing: 0) {
                typeOption(type: "folder", icon: "folder.fill", label: "文件夹", color: UIConstants.blue)

                if parentId != nil {
                    Divider().padding(.leading, 56)
                    typeOption(type: "file", icon: "doc.text.fill", label: "笔记", color: UIConstants.label3)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - 名称输入
    private var nameSection: some View {
        VStack(spacing: 0) {
            Text("名称")
                .font(.system(size: 13))
                .textCase(.uppercase)
                .foregroundColor(UIConstants.label3)
                .kerning(0.065)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
                .padding(.top, 14)

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
    }

    // MARK: - 文件子类型（普通文件 / 日程文件）
    private var fileSubTypeSection: some View {
        VStack(spacing: 0) {
            Text("文件类型")
                .font(.system(size: 13))
                .textCase(.uppercase)
                .foregroundColor(UIConstants.label3)
                .kerning(0.065)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
                .padding(.top, 14)

            VStack(spacing: 0) {
                subTypeOption(type: "note", icon: "doc.text.fill", label: "普通文件", color: UIConstants.label3)
                Divider().padding(.leading, 56)
                subTypeOption(type: "event", icon: "calendar.badge.clock", label: "日程文件", color: UIConstants.orange)
            }
            .cardStyle()
        }
    }

    // MARK: - 重复设置
    private var repeatSection: some View {
        VStack(spacing: 0) {
            Text("重复")
                .font(.system(size: 13))
                .textCase(.uppercase)
                .foregroundColor(UIConstants.label3)
                .kerning(0.065)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
                .padding(.top, 14)

            VStack(spacing: 0) {
                // 是否重复开关
                Toggle(isOn: $isRepeating) {
                    Text("是否重复")
                        .font(.system(size: 17))
                        .foregroundColor(UIConstants.label)
                        .kerning(-0.41)
                }
                .toggleStyle(SwitchToggleStyle(tint: UIConstants.blue))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if isRepeating {
                    Divider().padding(.leading, 16)

                    // 重复间隔值
                    HStack {
                        Text("间隔值")
                            .font(.system(size: 17))
                            .foregroundColor(UIConstants.label)
                            .kerning(-0.41)
                        Spacer()
                        Stepper("\(repeatValue)", value: $repeatValue, in: 1...999)
                            .labelsHidden()
                        Text("\(repeatValue)")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(UIConstants.blue)
                            .frame(minWidth: 30, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    Divider().padding(.leading, 16)

                    // 重复单位
                    Picker("单位", selection: $repeatUnit) {
                        ForEach(repeatUnits, id: \.0) { unit in
                            Text(unit.1).tag(unit.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Type Options
    private func typeOption(type: String, icon: String, label: String, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedType = type
            }
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

    private func subTypeOption(type: String, icon: String, label: String, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                fileSubType = type
            }
        } label: {
            HStack(spacing: 12) {
                RowIcon(systemName: icon, color: color)
                Text(label)
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.label)
                    .kerning(-0.41)
                Spacer()
                if fileSubType == type {
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

    // MARK: - Create
    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pid = parentId ?? ""
        Task {
            if selectedType == "folder" {
                await viewModel.createFolder(name: trimmed, parentId: parentId)
            } else {
                await viewModel.createFile(
                    name: trimmed, content: "", parentId: pid,
                    type: fileSubType,
                    repeatIntervalValue: isRepeating && fileSubType == "event" ? repeatValue : nil,
                    repeatIntervalUnit: isRepeating && fileSubType == "event" ? repeatUnit : nil
                )
            }
            await MainActor.run {
                dismiss()
            }
        }
    }
}
