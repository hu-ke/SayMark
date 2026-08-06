import SwiftUI

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
            Form {
                TextField("名称", text: $name)
            }
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onRename(trimmed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
