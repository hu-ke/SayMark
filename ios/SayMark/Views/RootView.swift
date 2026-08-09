import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var showNewItem = false
    @State private var locateFolderId: String?
    @State private var selectedTab = 0

    // 聊天
    @State private var showChat = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1 — 文件
            NavigationStack {
                FolderTreeView(viewModel: viewModel, locateFolderId: $locateFolderId)
                    .navigationTitle("语音记事本")
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button { showChat = true } label: {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .symbolVariant(showChat ? .fill : .none)
                            }
                            Button { showNewItem = true } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showNewItem) {
                        NewItemSheet(viewModel: viewModel, parentId: nil)
                    }
            }
            .tabItem {
                Label("文件", systemImage: "folder")
            }
            .tag(0)

            // Tab 2 — 日历
            CalendarView(treeViewModel: viewModel)
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }
                .tag(1)

            // Tab 3 — 提醒
            RemindersView()
                .tabItem {
                    Label("提醒", systemImage: "bell")
                }
                .tag(2)
        }
        .fullScreenCover(isPresented: $showChat) {
            ChatView()
        }
        .task {
            await viewModel.loadTree()
            LocationManager.shared.requestLocation()
            Task {
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
            let granted = await NotificationManager.shared.requestPermission()
            if granted {
                if let notes = try? await APIClient.shared.getReminderNotes() {
                    await NotificationManager.shared.scheduleNotifications(from: notes)
                }
            }
        }
    }
}
