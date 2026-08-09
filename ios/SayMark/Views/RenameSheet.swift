import SwiftUI

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let currentName: String
    var onRename: ((String) -> Void)?

    @State private var name: String

    init(title: String, currentName: String, onRename: ((String) -> Void)? = nil) {
        self.title = title
        self.currentName = currentName
        self.onRename = onRename
        _name = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义导航栏
                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 17))
                    .foregroundColor(UIConstants.blue)

                    Spacer()

                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .kerning(-0.41)

                    Spacer()

                    Button("确定") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onRename?(trimmed)
                        dismiss()
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
                    SectionHeader(title: "名称")
                        .padding(.top, 20)

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
                        .background(UIConstants.card)
                    }
                    .cardStyle()
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .background(UIConstants.background)
        }
    }
}
