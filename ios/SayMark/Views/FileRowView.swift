import SwiftUI

struct FileRowView: View {
    let file: NoteFile
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var showRename = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationLink(value: file) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // 文件图标
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                        .fill(file.isEvent ? DesignTokens.Color.accentBg : DesignTokens.Color.primaryBg)
                        .frame(width: 38, height: 38)

                    Image(systemName: file.isEvent ? "calendar.badge.clock" : "doc.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(file.isEvent ? DesignTokens.Color.accent : DesignTokens.Color.primary)
                }

                // 文件信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(DesignTokens.Font.body)
                        .fontWeight(.medium)
                        .foregroundStyle(DesignTokens.Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(formatRelativeDate(file.updatedAt))
                            .font(DesignTokens.Font.caption2)
                            .foregroundStyle(DesignTokens.Color.textTertiary)

                        if file.isEvent {
                            Circle()
                                .fill(DesignTokens.Color.textTertiary)
                                .frame(width: 3, height: 3)
                            Text("日程")
                                .font(DesignTokens.Font.caption2)
                                .foregroundStyle(DesignTokens.Color.accent)
                        }
                    }
                }

                Spacer()

                // 内容预览（仅笔记）
                if !file.isEvent, let content = file.content, !content.isEmpty {
                    Text(content.prefix(30).replacingOccurrences(of: "\n", with: " "))
                        .font(DesignTokens.Font.caption2)
                        .foregroundStyle(DesignTokens.Color.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .contextMenu {
            Button { showRename = true } label: {
                Label("重命名", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
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
            .tint(DesignTokens.Color.primary)
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

    /// 显示相对时间（刚刚 / X分钟前 / X小时前 / X天前）
    private func formatRelativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso + (iso.contains("Z") ? "" : "Z")) else {
            return String(iso.prefix(16).replacingOccurrences(of: "T", with: " "))
        }

        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60:       return "刚刚"
        case ..<3600:     return "\(Int(interval / 60))分钟前"
        case ..<86400:    return "\(Int(interval / 3600))小时前"
        case ..<604800:   return "\(Int(interval / 86400))天前"
        default:          return date.formatted(date: .numeric, time: .shortened)
        }
    }
}
