import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var showNewItem = false
    @State private var locateFolderId: String?
    @State private var selectedTab = 0

    // 聊天抽屉
    @State private var showChat = false

    var body: some View {
        ZStack {
            // 主 TabView
            TabView(selection: $selectedTab) {
                NavigationStack {
                    FolderTreeView(viewModel: viewModel, locateFolderId: $locateFolderId)
                        .navigationTitle("语音记事本")
                        .toolbar {
                            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
            }

            // 半透明遮罩
            if showChat {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissChat() }
                    .transition(.opacity)
            }

            // 聊天抽屉（全屏，从右侧滑入）
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Spacer()
                    ChatView()
                        .frame(width: geometry.size.width)
                        .background(Color(.systemBackground))
                        .offset(x: showChat ? 0 : geometry.size.width)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.width > 60 {
                                        dismissChat()
                                    }
                                }
                        )
                }
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showChat)

            // 底部中间聊天按钮（进入详情页时隐藏）
            if !viewModel.hideFloatingButton {
                VStack {
                    Spacer()
                    Button {
                        showChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Circle().fill(Color.accentColor).shadow(radius: 4))
                    }
                    .padding(.bottom, 74)  // TabBar 上方
                }
            }
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

    private func dismissChat() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showChat = false
        }
    }
}
