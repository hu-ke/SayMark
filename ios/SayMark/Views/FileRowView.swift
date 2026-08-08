import SwiftUI

struct FileRowView: View {
    let file: NoteFile
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var showRename = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationLink(value: file) {
            HStack {
                Image(systemName: file.isEvent ? "calendar.badge.clock" : "doc.text")
                    .foregroundStyle(file.isEvent ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                    Text(formatDate(file.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if file.isEvent {
                    Text("日程")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .contextMenu {
            Button("重命名") { showRename = true }
            Button("删除", role: .destructive) { showDeleteConfirm = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
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
        .confirmationDialog(
            "确定删除笔记？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteFile(id: file.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除笔记「\(file.name)」。此操作不可撤销。")
        }
    }

    /// 把 ISO 时间字符串（如 "2026-08-06T15:32:11.662000"）转为可读格式
    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso + (iso.contains("Z") ? "" : "Z")) {
            return date.formatted(date: .numeric, time: .shortened)
        }
        // fallback: 截取前19位 "YYYY-MM-DDTHH:MM:SS"
        return String(iso.prefix(16).replacingOccurrences(of: "T", with: " "))
    }
}
