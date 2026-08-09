import SwiftUI

struct NewItemSheet: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let parentId: String?
    @State private var name: String = ""
    @State private var type: ItemType = .folder
    @Environment(\.dismiss) private var dismiss

    enum ItemType: String, CaseIterable {
        case folder = "文件夹"
        case file = "笔记"
    }

    private var availableTypes: [ItemType] {
        parentId == nil ? [.folder] : ItemType.allCases
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                // 类型选择
                if availableTypes.count > 1 {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("类型")
                            .font(DesignTokens.Font.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                        Picker("类型", selection: $type) {
                            ForEach(availableTypes, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // 名称
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("名称")
                        .font(DesignTokens.Font.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                    TextField(
                        type == .folder ? "文件夹名称" : "笔记名称",
                        text: $name
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.lg)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        Task { await create() }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch type {
        case .folder:
            await viewModel.createFolder(name: trimmed, parentId: parentId)
        case .file:
            guard let pid = parentId else { return }
            await viewModel.createFile(name: trimmed, content: "", parentId: pid)
        }
        dismiss()
    }
}
