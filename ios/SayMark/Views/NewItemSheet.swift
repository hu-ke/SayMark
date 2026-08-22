import SwiftUI

struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FolderTreeViewModel
    var parentId: String?
    var preSelectedType: String? = nil

    @State private var selectedType: String

    init(viewModel: FolderTreeViewModel, parentId: String? = nil, preSelectedType: String? = nil) {
        self.viewModel = viewModel
        self.parentId = parentId
        self.preSelectedType = preSelectedType
        self._selectedType = State(initialValue: preSelectedType ?? "folder")
    }
    @State private var name = "新文件夹"

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

            VStack(spacing: 0) {
                // 类型选择
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

                // 名称输入
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
            .padding(.horizontal, 16)

            Spacer()
        }
        .background(UIConstants.background)
        .navigationBarHidden(true)
    }

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

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pid = parentId ?? ""
        Task {
            if selectedType == "folder" {
                await viewModel.createFolder(name: trimmed, parentId: parentId)
            } else {
                await viewModel.createFile(name: trimmed, content: "", parentId: pid)
            }
        }
        dismiss()
    }
}
