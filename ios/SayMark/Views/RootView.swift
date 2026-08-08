import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var showNewItem = false
    @State private var showVoiceInput = false
    @State private var locateFolderId: String?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FolderTreeView(viewModel: viewModel, locateFolderId: $locateFolderId)
                    .navigationTitle("语音记事本")
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            // 语音输入按钮
                            Button {
                                showVoiceInput = true
                            } label: {
                                Image(systemName: "mic")
                            }
                            // 新建按钮
                            Button {
                                showNewItem = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showNewItem) {
                        NewItemSheet(viewModel: viewModel, parentId: nil)
                    }
                    .sheet(isPresented: $showVoiceInput) {
                        CommandInputView(viewModel: viewModel, onSelectFolder: { folderId in
                            locateFolderId = folderId
                            viewModel.locate(folderId: folderId)
                        })
                    }
            }
            .tabItem {
                Label("文件", systemImage: "folder")
            }
            .tag(0)

            CalendarView(treeViewModel: viewModel)
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }
                .tag(1)

            RemindersView()
                .tabItem {
                    Label("提醒", systemImage: "bell")
                }
                .tag(2)

            ChatView()
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(3)
        }
        .task {
            await viewModel.loadTree()
            LocationManager.shared.requestLocation()
            // 异步同步位置到后端用户 Profile
            Task {
                // 等位置获取完成（最多等 3 秒）
                for _ in 0..<30 {
                    if let lat = LocationManager.shared.latitude,
                       let lon = LocationManager.shared.longitude {
                        try? await APIClient.shared.requestEmpty(
                            path: "/api/user/location?device_id=\(DeviceID.shared.id)",
                            method: "PUT",
                            body: ["latitude": lat, "longitude": lon]
                        )
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
}
