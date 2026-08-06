import SwiftUI

struct NewItemSheet: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let parentId: String?
    @State private var name: String = ""
    @State private var type: ItemType = .folder
    @Environment(\.dismiss) private var dismiss

    enum ItemType: String, CaseIterable {
        case folder = "文件夹"
        case file = "文件"
    }

    /// 根目录下仅允许新建文件夹
    private var availableTypes: [ItemType] {
        parentId == nil ? [.folder] : ItemType.allCases
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $type) {
                    ForEach(availableTypes, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("名称", text: $name)
            }
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
            // 文件必须归属某个文件夹
            guard let pid = parentId else { return }
            await viewModel.createFile(name: trimmed, content: "", parentId: pid)
        }
        dismiss()
    }
}
