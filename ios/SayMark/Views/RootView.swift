import SwiftUI

// MARK: - Recording Zone
enum RecZone {
    case normal
    case cancel
    case text
}

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var locateFolderId: String?
    @State private var selectedTab = 0

    // 聊天抽屉
    @State private var showChat = false

    // 录音浮层
    @State private var recordingZone: RecZone? = nil
    @State private var showVoiceSheet = false

    var body: some View {
        ZStack {
            // 主内容区
            VStack(spacing: 0) {
                // 页面切换
                ZStack {
                    switch selectedTab {
                    case 0:
                        FolderTreeView(
                            viewModel: viewModel,
                            locateFolderId: $locateFolderId,
                            onNote: { /* file detail handled via NavigationLink */ },
                            onChat: { showChat = true },
                            onRecord: { recordingZone = .normal }
                        )
                    case 1:
                        CalendarView(treeViewModel: viewModel)
                    case 2:
                        RemindersView()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 自定义 TabBar
                if selectedTab <= 2 && !viewModel.hideFloatingButton {
                    SayMarkTabBar(selectedTab: $selectedTab)
                }
            }

            // FAB 录音按钮
            if selectedTab == 0 && !viewModel.hideFloatingButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FABButton {
                            recordingZone = .normal
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 98)
                    }
                }
            }

            // 半透明遮罩（聊天抽屉）
            if showChat {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissChat() }
                    .transition(.opacity)
            }

            // 聊天抽屉（从右侧滑入）
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

            // 录音覆盖层
            if let zone = recordingZone {
                RecordingOverlay(zone: zone, onClose: { recordingZone = nil })
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .background(UIConstants.background)
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

// MARK: - Recording Overlay
struct RecordingOverlay: View {
    let zone: RecZone
    let onClose: () -> Void

    @State private var transcript = "明天下午三点产品路线图评审..."
    @State private var dragOffset: CGFloat = 0
    @State private var currentZone: RecZone = .normal

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                switch currentZone {
                case .normal:
                    // 波形动画
                    HStack(spacing: 7) {
                        ForEach(0..<6, id: \.self) { i in
                            WaveBar(index: i)
                        }
                    }
                    .padding(.bottom, 32)

                    Text("松开 发送")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 14)

                    Text(transcript)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .lineLimit(3)
                        .padding(.bottom, 60)

                case .cancel:
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(UIConstants.red.opacity(0.2))
                                .frame(width: 88 + 28, height: 88 + 28)
                            Circle()
                                .fill(UIConstants.red)
                                .frame(width: 88, height: 88)
                            Image(systemName: "xmark")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Text("松开 取消")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(UIConstants.red)
                    }
                    .padding(48)
                    .background(UIConstants.red.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                case .text:
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(UIConstants.green.opacity(0.2))
                                .frame(width: 88 + 28, height: 88 + 28)
                            Circle()
                                .fill(UIConstants.green)
                                .frame(width: 88, height: 88)
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundColor(.white)
                        }
                        Text("松开 转文字")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(UIConstants.green)
                    }
                    .padding(48)
                    .background(UIConstants.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                }

                Spacer()

                // 底部提示
                if currentZone == .normal {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                            Text("松开取消")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Text("转文字")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.6))
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }

                // 底部麦克风按钮
                ZStack {
                    Circle()
                        .fill(currentZone == .cancel ? UIConstants.red :
                               currentZone == .text ? UIConstants.green : UIConstants.blue)
                        .frame(width: 72, height: 72)
                        .shadow(color: (currentZone == .cancel ? UIConstants.red :
                                         currentZone == .text ? UIConstants.green : UIConstants.blue).opacity(0.25),
                                radius: 10)
                    TabIcon(type: "mic", size: 32, color: .white, strokeWidth: 2)
                }
                .padding(.bottom, 50)
            }
        }
        .onTapGesture { onClose() }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    dragOffset = value.translation.width
                    if dragOffset < -60 {
                        currentZone = .text
                    } else if dragOffset > 60 {
                        currentZone = .cancel
                    } else {
                        currentZone = .normal
                    }
                }
                .onEnded { value in
                    let finalOffset = value.translation.width
                    if finalOffset < -80 {
                        // 转文字
                        onClose()
                    } else if finalOffset > 80 {
                        // 取消
                        onClose()
                    } else {
                        // 发送
                        onClose()
                    }
                    currentZone = .normal
                    dragOffset = 0
                }
        )
    }
}

// MARK: - Wave Bar Animation
struct WaveBar: View {
    let index: Int
    let animations: [(String, Double)] = [
        ("w1", 0.68), ("w2", 0.52), ("w3", 0.78),
        ("w4", 0.61), ("w5", 0.74), ("w6", 0.56)
    ]
    let minHeights: [CGFloat] = [10, 22, 14, 26, 12, 20]
    let maxHeights: [CGFloat] = [28, 10, 32, 10, 24, 8]

    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: 4, height: animate ? maxHeights[index] : minHeights[index])
            .animation(
                .easeInOut(duration: animations[index].1)
                .repeatForever(autoreverses: true),
                value: animate
            )
            .onAppear { animate = true }
    }
}
