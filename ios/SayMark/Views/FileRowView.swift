import SwiftUI

/// Figma 风格的文件行，带导航箭头和"日程"标签
struct FileRowView: View {
    let file: NoteFile
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var showRename = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationLink(value: file) {
            HStack(spacing: 0) {
                // 文件图标
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(file.isEvent ? DesignColor.orange : DesignColor.label3)
                        .frame(width: 28, height: 28)
                    Image(systemName: file.isEvent ? "calendar.badge.clock" : "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(file.name)
                            .font(.system(size: 17))
                            .foregroundStyle(DesignColor.label)
                            .lineLimit(1)
                        if file.isEvent {
                            Text("日程")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(DesignColor.orange)
                                )
                        }
                    }
                    Text(formatDate(file.updatedAt))
                        .font(.system(size: 13))
                        .foregroundStyle(DesignColor.label3)
                }
                .padding(.leading, 12)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignColor.label3.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.leading, 36)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                showRename = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
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
            .tint(DesignColor.blue)
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

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso + (iso.contains("Z") ? "" : "Z")) {
            let now = Date()
            if Calendar.current.isDateInToday(date) {
                return "今天 " + date.formatted(date: .omitted, time: .shortened)
            } else if Calendar.current.isDateInYesterday(date) {
                return "昨天 " + date.formatted(date: .omitted, time: .shortened)
            }
            return date.formatted(date: .numeric, time: .shortened).replacingOccurrences(of: "/", with: "月").replacingOccurrences(of: "年", with: "年").replacingOccurrences(of: "月", with: "月")
        }
        return String(iso.prefix(16).replacingOccurrences(of: "T", with: " "))
    }
}
