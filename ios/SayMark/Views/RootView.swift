import SwiftUI

/// Figma 风格的主视图：TabBar + 文件列表/日历/提醒 + FAB + 聊天抽屉
struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var showNewItem = false
    @State private var locateFolderId: String?
    @State private var selectedTab = 0
    @State private var showChat = false

    // 录音覆盖层
    @State private var showRecording = false
    @State private var recordingZone: RecordingZone = .normal

    enum RecordingZone {
        case normal, cancel, text
    }

    var body: some View {
        ZStack {
            // 主 TabView
            TabView(selection: $selectedTab) {
                NavigationStack {
                    FolderTreeView(
                        viewModel: viewModel,
                        locateFolderId: $locateFolderId,
                        showNewItem: $showNewItem,
                        showChat: $showChat
                    )
                    .navigationTitle("SayMark")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button {
                                showChat = true
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DesignColor.blue.opacity(0.1))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(DesignColor.blue)
                                }
                            }
                            Button {
                                showNewItem = true
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DesignColor.blue)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showNewItem) {
                        NewItemSheet(viewModel: viewModel, parentId: nil)
                    }
                }
                .tabItem {
                    Label("文件", systemImage: "doc.text")
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
            .tint(DesignColor.blue)

            // 浮动录音按钮（FAB，右下角，TabBar 上方）
            if !viewModel.hideFloatingButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRecording = true
                                recordingZone = .normal
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(DesignColor.blue)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: DesignColor.blue.opacity(0.45), radius: 12, y: 4)
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 14)
                }
            }

            // 录音覆盖层
            if showRecording {
                recordingOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(100)
            }

            // 半透明遮罩
            if showChat {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissChat() }
                    .transition(.opacity)
                    .zIndex(50)
            }

            // 聊天抽屉（全屏，从右侧滑入）
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Spacer()
                    ChatView(onClose: { dismissChat() })
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
            .zIndex(60)
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

    // MARK: - 录音覆盖层（Figma 风格三区）

    private var recordingOverlay: some View {
        RecordingOverlayView(
            zone: $recordingZone,
            isPresented: $showRecording,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRecording = false
                }
            }
        )
    }

    private func dismissChat() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showChat = false
        }
    }
}

// MARK: - 按下缩放按钮样式

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 录音覆盖层（Figma 风格）

/// 三区录音覆盖层：正常录音 / 取消 / 转文字
private struct RecordingOverlayView: View {
    @Binding var zone: RootView.RecordingZone
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @State private var waveHeights: [CGFloat] = [10, 22, 14, 26, 12, 20]
    @State private var waveTimer: Timer?

    var body: some View {
        ZStack {
            // 半透明模糊背景
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            // 分区内容
            switch zone {
            case .normal:
                normalZone
            case .cancel:
                cancelZone
            case .text:
                textZone
            }

            // 底部麦克风
            VStack {
                Spacer()
                Circle()
                    .fill(zoneColor)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: zone == .cancel ? "xmark" : zone == .text ? "textformat.alt" : "mic.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: zoneColor.opacity(0.35), radius: 16)
                    .padding(.bottom, 96)
            }
        }
        .onAppear { startWaveAnimation() }
        .onDisappear { waveTimer?.invalidate() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dy = value.translation.height
                    let dx = value.translation.width
                    let threshold: CGFloat = 60
                    if dy < -threshold {
                        zone = dx < 0 ? .cancel : .text
                    } else {
                        zone = .normal
                    }
                }
                .onEnded { _ in onDismiss() }
        )
        .onTapGesture { onDismiss() }
    }

    private var zoneColor: Color {
        switch zone {
        case .normal: return DesignColor.blue
        case .cancel: return DesignColor.red
        case .text: return DesignColor.green
        }
    }

    // MARK: - 正常录音区

    private var normalZone: some View {
        VStack(spacing: 16) {
            // 波形动画
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 4, height: waveHeights[i])
                        .animation(.easeInOut(duration: 0.3), value: waveHeights[i])
                }
            }
            .frame(height: 30)
            .padding(.bottom, 8)

            Text("松开 发送")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Text("明天下午三点产品路线图评审...")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)

            // 底部提示
            HStack(spacing: 48) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text("松开取消")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Text("转文字")
                        .font(.caption)
                    Image(systemName: "textformat.alt")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 60)
        }
    }

    // MARK: - 取消区

    private var cancelZone: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(DesignColor.red)
                    .frame(width: 88, height: 88)
                    .shadow(color: DesignColor.red.opacity(0.3), radius: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("松开 取消")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DesignColor.red)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 64)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(DesignColor.red.opacity(0.18))
        )
    }

    // MARK: - 转文字区

    private var textZone: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(DesignColor.green)
                    .frame(width: 88, height: 88)
                    .shadow(color: DesignColor.green.opacity(0.3), radius: 20)
                Image(systemName: "textformat.alt")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            Text("松开 转文字")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DesignColor.green)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 64)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(DesignColor.green.opacity(0.18))
        )
    }

    // MARK: - 波形动画

    private func startWaveAnimation() {
        waveTimer?.invalidate()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                waveHeights = [
                    CGFloat.random(in: 8...30),
                    CGFloat.random(in: 10...28),
                    CGFloat.random(in: 12...32),
                    CGFloat.random(in: 8...28),
                    CGFloat.random(in: 10...26),
                    CGFloat.random(in: 8...24),
                ]
            }
        }
    }
}
