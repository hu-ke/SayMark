import SwiftUI

struct FileRowView: View {
    let file: NoteFile
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var showRename = false

    var body: some View {
        NavigationLink(value: file) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(file.name)
                Spacer()
            }
        }
        .contextMenu {
            Button("重命名") { showRename = true }
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteFile(id: file.id) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.deleteFile(id: file.id) }
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(initialName: file.name) { newName in
                Task { await viewModel.renameFile(id: file.id, name: newName) }
            }
        }
    }
}
