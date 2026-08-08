import Foundation
import Speech
import AVFoundation
import Combine

/// 语音识别器（zh-CN，SFSpeechRecognizer + AVAudioEngine）
/// 注意：iOS 模拟器对语音识别支持有限，可能无法识别；真机可用。
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    /// 语音识别是否可用（模拟器或未授权时为 false）
    @Published var isAvailable: Bool = false

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        // 模拟器上 zh-CN 可能返回 nil，不要强解包
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        self.isAvailable = self.speechRecognizer?.isAvailable ?? false
    }

    deinit {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// 请求语音识别与麦克风权限，返回是否全部授权
    func requestAuthorization() async -> Bool {
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            self.errorMessage = "未授权语音识别，请在设置中开启"
            return false
        }
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micGranted else {
            self.errorMessage = "未授权麦克风，请在设置中开启"
            return false
        }
        return true
    }

    /// 开始录音
    func startRecording() async {
        guard !isRecording else { return }
        guard let speechRecognizer = speechRecognizer else {
            self.errorMessage = "语音识别不可用（模拟器可能不支持，请用真机或在下方手动输入）"
            return
        }
        guard speechRecognizer.isAvailable else {
            self.errorMessage = "语音识别不可用，请用真机或在下方手动输入"
            return
        }
        let authorized = await requestAuthorization()
        guard authorized else { return }

        // 重置状态
        transcript = ""
        errorMessage = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.errorMessage = "音频会话配置失败: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.errorMessage = "无法创建识别请求"
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // 防御：模拟器上 sampleRate 可能为 0，installTap 会 abort
        guard recordingFormat.sampleRate > 0 else {
            self.errorMessage = "音频格式无效（模拟器可能不支持录音），请用真机或在下方手动输入"
            return
        }
        inputNode.removeTap(onBus: 0) // 防止重复安装 tap 导致崩溃
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.errorMessage = "音频引擎启动失败: \(error.localizedDescription)"
            return
        }

        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if let error = error {
                Task { @MainActor in
                    self.errorMessage = "识别错误: \(error.localizedDescription)"
                    self.stopRecording()
                }
            }
        }
    }

    /// 停止录音
    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
