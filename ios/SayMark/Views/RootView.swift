import SwiftUI

// MARK: - Recording Zone
enum RecZone {
    case normal
    case cancel
    case text
}

// MARK: - Recording Result
enum RecordingResult {
    case send(String)       // 直接发送转义文字
    case textConfirm(String) // 转文字后需要确认
    case cancelled           // 取消
}

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var voice = VoiceRecorder()
    @State private var locateFolderId: String?
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    // 聊天
    @State private var showChat = false
    @State private var pendingMessage: String?

    var body: some View {
        ZStack {
            // 主内容区
            VStack(spacing: 0) {
                ZStack {
                    switch selectedTab {
                    case 0:
                        FolderTreeView(
                            viewModel: viewModel,
                            locateFolderId: $locateFolderId,
                            onNote: { },
                            onChat: { showChat = true },
                            onRecord: { /* now handled by long-press on TabBar FAB */ }
                        )
                    case 1:
                        CalendarView(treeViewModel: viewModel)
                    case 2:
                        AppointmentsView(treeViewModel: viewModel)
                    case 3:
                        AlarmsView(treeViewModel: viewModel)
                    case 4:
                        SettingsView()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !viewModel.hideTabBar {
                    SayMarkTabBar(
                        selectedTab: $selectedTab,
                        showMic: !viewModel.hideFloatingButton,
                        onRecordStart: { voice.start() },
                        onRecordChanged: { zone in
                            voice.updateZone(zone)
                        },
                        onRecordEnd: { _ in
                            voice.end()
                        }
                    )
                }
            }

            // 聊天全屏
            if showChat {
                ChatView(viewModel: chatViewModel, onClose: { dismissChat() }, initialMessage: pendingMessage)
                    .transition(.move(edge: .trailing))
                    .zIndex(50)
            }
        }
        .voiceRecorderOverlay(voice)
        .background(UIConstants.background)
        .onChange(of: selectedTab) { _, newTab in
            // 每次切回「文件」列表页都刷新目录树，保证聊天/其它操作后的增删改及时可见
            if newTab == 0 {
                Task { await viewModel.loadTree() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 回到前台时重新同步本地通知，避免新增/修改安排闹钟后遗漏提醒
            if newPhase == .active {
                Task { await NotificationManager.shared.refreshFromServer() }
            }
        }
        .task {
            // 识别结果路由：松开发送 → 打开聊天
            voice.onResult = { result in
                if case .send(let text) = result {
                    sendToChat(text)
                }
            }

            await viewModel.loadTree()
            LocationManager.shared.requestLocation()
            // 预请求麦克风权限，避免首次长按录音时被系统弹窗打断手势
            _ = await voice.requestAuthorization()
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
                await NotificationManager.shared.refreshFromServer()
            }
        }
    }

    private func sendToChat(_ text: String) {
        pendingMessage = text
        showChat = true
    }

    private func dismissChat() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showChat = false
        }
        pendingMessage = nil
        // 关闭聊天返回列表页时刷新目录树与通知（聊天中可能增删改了笔记/安排/闹钟）
        Task { await viewModel.loadTree() }
        Task { await NotificationManager.shared.refreshFromServer() }
    }
}

// MARK: - Voice Recorder Overlay & Gesture（统一的录音交互，供各入口复用）

extension View {
    /// 统一的录音蒙层 + 转文字确认弹窗
    func voiceRecorderOverlay(_ recorder: VoiceRecorder) -> some View {
        self
            .overlay {
                if let zone = recorder.zone {
                    RecordingOverlay(
                        zone: zone,
                        transcript: recorder.transcript,
                        isProcessing: recorder.isProcessing,
                        onClose: { recorder.cancel() }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .overlay {
                if recorder.showTextConfirm {
                    TextConfirmSheet(
                        text: recorder.confirmText,
                        onCancel: { recorder.showTextConfirm = false },
                        onSend: { recorder.confirmSend($0) }
                    )
                    .transition(.opacity)
                    .zIndex(110)
                }
            }
    }

    /// 统一的「按住说话 + 左移取消 + 右移转文字」手势
    func voiceRecordGesture(recorder: VoiceRecorder) -> some View {
        self.simultaneousGesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        recorder.start()
                        if let drag = drag {
                            let w = drag.translation.width
                            let h = drag.translation.height
                            if h < -30 && w < -30 {
                                recorder.updateZone(.cancel)
                            } else if h < -30 && w > 30 {
                                recorder.updateZone(.text)
                            } else {
                                recorder.updateZone(.normal)
                            }
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    recorder.end()
                }
        )
    }
}

// MARK: - Recording Overlay (with real-time transcript)
struct RecordingOverlay: View {
    let zone: RecZone
    let transcript: String
    var isProcessing: Bool = false
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            if isProcessing {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("识别中...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            } else {
                VStack(spacing: 0) {
                    Spacer()

                    switch zone {
                    case .normal:
                        HStack(spacing: 7) {
                            ForEach(0..<6, id: \.self) { i in WaveBar(index: i) }
                        }
                        .padding(.bottom, 32)

                        Text("松开 发送")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 14)

                        Text(transcript.isEmpty ? "正在聆听..." : transcript)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                            .lineLimit(4)
                            .padding(.bottom, 60)

                    case .cancel:
                        VStack(spacing: 18) {
                            ZStack {
                                Circle().fill(UIConstants.red.opacity(0.2)).frame(width: 116, height: 116)
                                Circle().fill(UIConstants.red).frame(width: 88, height: 88)
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
                                Circle().fill(UIConstants.green.opacity(0.2)).frame(width: 116, height: 116)
                                Circle().fill(UIConstants.green).frame(width: 88, height: 88)
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

                    if zone == .normal {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("松开取消").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Text("转文字").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6))
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                    }

                    ZStack {
                        Circle()
                            .fill(zone == .cancel ? UIConstants.red :
                                   zone == .text ? UIConstants.green : UIConstants.blue)
                            .frame(width: 72, height: 72)
                            .shadow(color: (zone == .cancel ? UIConstants.red :
                                             zone == .text ? UIConstants.green : UIConstants.blue).opacity(0.25), radius: 10)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// MARK: - Text Confirm Sheet
struct TextConfirmSheet: View {
    let text: String
    let onCancel: () -> Void
    let onSend: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    SheetHandle()

                    HStack(spacing: 8) {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(UIConstants.label3)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.fill2))
                        }
                        Spacer()
                        Text("确认文字").font(.system(size: 17, weight: .bold))
                        Spacer()
                        Button {
                            onSend(text)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(UIConstants.green))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)

                    ScrollView {
                        Text(text)
                            .font(.system(size: 16))
                            .foregroundColor(UIConstants.label)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
                .background(UIConstants.card)
                .clipShape(RoundedCorner(tl: 20, tr: 20))
                .shadow(color: .black.opacity(0.2), radius: 48, y: -8)
                .padding(.bottom, 34)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Wave Bar Animation
struct WaveBar: View {
    let index: Int
    let minHeights: [CGFloat] = [10, 22, 14, 26, 12, 20]
    let maxHeights: [CGFloat] = [28, 10, 32, 10, 24, 8]
    let durations: [Double] = [0.68, 0.52, 0.78, 0.61, 0.74, 0.56]

    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white)
            .frame(width: 4, height: animate ? maxHeights[index] : minHeights[index])
            .animation(
                .easeInOut(duration: durations[index]).repeatForever(autoreverses: true),
                value: animate
            )
            .onAppear { animate = true }
    }
}
