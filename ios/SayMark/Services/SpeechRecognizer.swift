import Foundation
import AVFoundation
import Speech
import Combine

/// 语音录制 + 实时识别（豆包 Seed-ASR 2.0 优先，本地 SFSpeechRecognizer 兜底）。
///
/// - 录音过程中，SFSpeechRecognizer 实时产出部分识别文本（实时体验）。
/// - 松手后，把音频上传后端走豆包识别；豆包失败/为空时，兜底用本地识别结果。
/// 同时承载「按住说话」交互状态（分区：正常 / 取消 / 转文字）。
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false       // 松手后等待豆包识别
    @Published var transcript = ""            // 本地实时识别文本（也用于兜底）
    @Published var errorMessage: String?
    @Published var zone: RecZone? = nil        // 录音分区（nil=未录音）
    @Published var showTextConfirm = false
    @Published var confirmText = ""

    /// 识别结果路由回调（.send 直接发送 / .cancelled 取消）
    var onResult: ((RecordingResult) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let pcmAccumulator = PCMAccumulator()
    private var nativeSampleRate: Double = 44100

    func requestAuthorization() async -> Bool {
        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechAuth else {
            errorMessage = "未授权语音识别，请在设置中开启"
            return false
        }
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micGranted else {
            errorMessage = "未授权麦克风，请在设置中开启"
            return false
        }
        return true
    }

    // MARK: - 录音（本地实时识别 + 采集 PCM）

    func startRecording() async {
        guard !isRecording else { return }
        let authorized = await requestAuthorization()
        guard authorized else { return }

        transcript = ""
        errorMessage = nil
        isProcessing = false

        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              speechRecognizer.isAvailable else {
            errorMessage = "语音识别不可用（模拟器可能不支持，请用真机）"
            return
        }
        self.speechRecognizer = speechRecognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "音频会话配置失败：\(error.localizedDescription)"
            return
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            errorMessage = "音频格式无效（模拟器可能不支持录音），请用真机"
            return
        }
        // 使用输入节点的原始格式建 tap，避免自定义格式导致的 format mismatch 崩溃；
        // 豆包需要的 16kHz 音频在停止录音后再统一重采样。
        nativeSampleRate = inputFormat.sampleRate

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "无法创建识别请求"
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        pcmAccumulator.reset()
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            recognitionRequest.append(buffer)
            // 采集原始 Float32（单声道），结束后重采样到 16kHz
            if let floatData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                let byteCount = frames * MemoryLayout<Float>.size
                floatData.withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
                    self.pcmAccumulator.append(ptr, count: byteCount)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "音频引擎启动失败：\(error.localizedDescription)"
            return
        }

        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcript = text
                }
            }
            if let error = error {
                Task { @MainActor in
                    if self.errorMessage == nil {
                        self.errorMessage = "识别失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// 结束录音：豆包优先，失败兜底本地识别。返回最终文本。
    @discardableResult
    func stopRecording() async -> String {
        guard isRecording else { return "" }
        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // 上传豆包识别（等待期间本地识别也会产出最终结果）
        let wav = buildWAV(from: floatTo16kPCM(pcmAccumulator.snapshot()))
        var doubaoText = ""
        if !wav.isEmpty {
            do {
                doubaoText = try await APIClient.shared.recognizeSpeech(
                    audioBase64: wav.base64EncodedString(),
                    format: "wav",
                    sampleRate: 16000
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // 兜底：本地 SFSpeechRecognizer 识别结果
        let localText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = doubaoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = d.isEmpty ? localText : d
        transcript = final
        return final
    }

    // MARK: - 交互（按住说话 + 左移取消 + 右移转文字）

    func start() {
        guard zone == nil else { return }
        zone = .normal
        showTextConfirm = false
        Task { await startRecording() }
    }

    func updateZone(_ z: RecZone) {
        guard zone != nil else { return }
        if zone != z { zone = z }
    }

    func end() {
        guard zone != nil else { return }
        let finalZone = zone ?? .normal

        // 取消：只停止录音，不上传识别（避免无谓的接口请求）
        if finalZone == .cancel {
            zone = nil
            stopEngineOnly()
            return
        }

        isProcessing = true
        Task {
            let text = await stopRecording()
            isProcessing = false
            zone = nil
            switch finalZone {
            case .cancel:
                break
            case .normal:
                if !text.isEmpty { onResult?(.send(text)) }
            case .text:
                confirmText = text
                if !text.isEmpty { showTextConfirm = true }
            }
        }
    }

    func cancel() {
        zone = nil
        showTextConfirm = false
        stopEngineOnly()
    }

    /// 仅停止录音并释放资源，不上传识别
    private func stopEngineOnly() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func confirmSend(_ text: String) {
        showTextConfirm = false
        onResult?(.send(text))
    }

    // MARK: - WAV 组装

    /// 把采集到的原始 Float32 PCM 重采样到 16kHz，并转成 Int16 PCM。
    private func floatTo16kPCM(_ floatBytes: Data) -> Data {
        guard !floatBytes.isEmpty else { return Data() }
        let samples: [Float] = floatBytes.withUnsafeBytes { raw in
            let count = raw.count / MemoryLayout<Float>.size
            let base = raw.bindMemory(to: Float.self).baseAddress!
            return Array(UnsafeBufferPointer(start: base, count: count))
        }

        // 重采样到 16kHz（线性插值）
        var resampled: [Float]
        if abs(nativeSampleRate - 16000) < 1 {
            resampled = samples
        } else if samples.count > 1 {
            let ratio = nativeSampleRate / 16000.0
            let outCount = Int(Double(samples.count) / ratio)
            var out = [Float](repeating: 0, count: max(0, outCount))
            for i in 0..<out.count {
                let src = Double(i) * ratio
                let i0 = Int(src)
                let i1 = min(i0 + 1, samples.count - 1)
                let frac = Float(src - Double(i0))
                out[i] = samples[i0] * (1 - frac) + samples[i1] * frac
            }
            resampled = out
        } else {
            resampled = []
        }

        // Float32 -> Int16
        var int16s = [Int16](repeating: 0, count: resampled.count)
        for i in 0..<resampled.count {
            let v = max(-1.0, min(1.0, resampled[i]))
            int16s[i] = Int16(v * 32767.0)
        }
        return int16s.withUnsafeBytes { Data($0) }
    }

    private func buildWAV(from pcm: Data) -> Data {
        guard !pcm.isEmpty else { return Data() }
        var wav = Data()
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)

        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(u32le(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(u32le(16))
        wav.append(u16le(1))            // PCM
        wav.append(u16le(channels))
        wav.append(u32le(sampleRate))
        wav.append(u32le(byteRate))
        wav.append(u16le(blockAlign))
        wav.append(u16le(bitsPerSample))
        wav.append(contentsOf: Array("data".utf8))
        wav.append(u32le(dataSize))
        wav.append(pcm)
        return wav
    }

    private func u32le(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    private func u16le(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }
}

/// 线程安全的 PCM 字节累积器（供音频 tap 回调使用）
private final class PCMAccumulator {
    private let lock = NSLock()
    private var data = Data()

    func reset() {
        lock.lock(); defer { lock.unlock() }
        data = Data()
    }

    func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        data.append(bytes, count: count)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
