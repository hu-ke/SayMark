import SwiftUI

/// Figma 风格的重命名界面：卡片式输入
struct RenameSheet: View {
    let initialName: String
    let onRename: (String) -> Void
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(initialName: String, onRename: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onRename = onRename
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Text("名称")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignColor.label3)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 20)
                .padding(.bottom, 6)
                .padding(.leading, 16)

                // 卡片式输入
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        TextField("名称", text: $name)
                            .font(.system(size: 17))
                            .foregroundStyle(DesignColor.label)

                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(DesignColor.label3)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
                .background(DesignColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                Spacer()
            }
            .background(DesignColor.background)
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignColor.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onRename(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                        ? DesignColor.blue.opacity(0.35)
                        : DesignColor.blue)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
