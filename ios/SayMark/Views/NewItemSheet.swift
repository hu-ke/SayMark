import SwiftUI

/// Figma 风格的新建条目界面：卡片式列表
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
            ScrollView {
                VStack(spacing: 0) {
                    // 类型选择
                    sectionHeader("类型")
                    CardView {
                        ForEach(availableTypes, id: \.self) { t in
                            Button {
                                type = t
                            } label: {
                                HStack(spacing: 0) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(t == .folder ? DesignColor.blue : DesignColor.label3)
                                            .frame(width: 28, height: 28)
                                        Image(systemName: t == .folder ? "folder.fill" : "doc.text")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                    }
                                    Text(t.rawValue)
                                        .font(.system(size: 17))
                                        .foregroundStyle(DesignColor.label)
                                        .padding(.leading, 12)
                                    Spacer()
                                    if type == t {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(DesignColor.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            if t != availableTypes.last {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }

                    // 名称输入
                    sectionHeader("名称")
                    CardView {
                        HStack(spacing: 0) {
                            TextField("输入名称", text: $name)
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            .background(DesignColor.background)
            .navigationTitle("新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DesignColor.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("创建") {
                        Task { await create() }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(DesignColor.label3)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// 白色圆角卡片容器
private struct CardView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DesignColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
