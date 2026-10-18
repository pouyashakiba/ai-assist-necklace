import Foundation
import AVFoundation
import Speech
import Combine

@MainActor final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var transcript = ""
    var onTranscript: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var renewal: Task<Void, Never>?
    private var speechCompletion: CheckedContinuation<Void, Error>?
    private var tapInstalled = false
    private var sessionID = UUID()
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init(); synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                self?.stopListening(); self?.stopSpeaking()
                self?.onFailure?("Listening was interrupted by iOS. Tap Listen to start it again.")
            }
        }
    }

    var offlineRecognitionReady: Bool { recognizer?.supportsOnDeviceRecognition == true }
    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    func requestPermissions() async throws {
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard speech == .authorized else { throw CompanionError.unavailable("Allow Speech Recognition for Little Companion in iPhone Settings.") }
        let mic = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard mic else { throw CompanionError.unavailable("Allow Microphone access for Little Companion in iPhone Settings.") }
        guard offlineRecognitionReady else { throw CompanionError.unavailable("Offline English speech recognition isn't ready. Download English speech assets in iOS Settings and try again. Typing still works.") }
    }

    func startListening() throws {
        stopListening()
        guard offlineRecognitionReady, let recognizer else { throw CompanionError.unavailable("On-device English speech recognition isn't available.") }
        let id = UUID(); sessionID = id
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        request = recognitionRequest; transcript = ""
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CompanionError.unavailable("The microphone audio route isn't ready. Try again.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in recognitionRequest.append(buffer) }
        tapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    if result.isFinal { self.stopListening(); self.onTranscript?(text, true); return }
                    self.onTranscript?(text, false)
                }
                if let error, self.isRecording {
                    self.stopListening(); self.onFailure?("Speech listening stopped: \(error.localizedDescription). Tap Listen to resume.")
                }
            }
        }
        engine.prepare()
        do { try engine.start(); isRecording = true }
        catch { stopListening(); throw error }
        renewal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled, let self, self.sessionID == id, self.isRecording else { return }
            let transcript = self.transcript
            self.stopListening()
            self.onTranscript?(transcript, true)
        }
    }

    func stopListening() {
        sessionID = UUID(); renewal?.cancel(); renewal = nil
        isRecording = false
        engine.stop(); if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognitionTask?.cancel(); recognitionTask = nil; request = nil
    }

    func transcribe(pcm: Data) async throws -> String {
        stopListening()
        guard let recognizer, offlineRecognitionReady else { throw CompanionError.unavailable("Offline English speech recognition isn't available on this iPhone.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try AudioPacket.wav(pcm: pcm, sampleRate: 16000).write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
        defer { try? FileManager.default.removeItem(at: url) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    guard !finished else { return }
                    if let error { finished = true; continuation.resume(throwing: error) }
                    else if let result, result.isFinal { finished = true; continuation.resume(returning: result.bestTranscription.formattedString) }
                }
            }
        }
    }

    private func utterance(_ text: String, voiceID: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? voices.first(where: { $0.language == "en-US" }) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47; utterance.pitchMultiplier = 1.02; utterance.preUtteranceDelay = 0.04; utterance.postUtteranceDelay = 0.08
        return utterance
    }

    func speak(_ text: String, voiceID: String) async throws {
        stopListening(); stopSpeaking()
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .spokenAudio)
        try audio.setActive(true)
        isSpeaking = true
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                speechCompletion = continuation
                synthesizer.speak(utterance(text, voiceID: voiceID))
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stopSpeaking() } }
    }

    func renderPCM(_ text: String, voiceID: String) async throws -> Data {
        stopListening(); stopSpeaking()
        return try await withCheckedThrowingContinuation { continuation in
            let collector = RenderCollector(continuation)
            synthesizer.write(utterance(text, voiceID: voiceID)) { buffer in collector.append(buffer) }
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate); isSpeaking = false
        let completion = speechCompletion; speechCompletion = nil; completion?.resume(throwing: CancellationError())
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false; let continuation = self?.speechCompletion; self?.speechCompletion = nil; continuation?.resume() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false; let continuation = self?.speechCompletion; self?.speechCompletion = nil; continuation?.resume(throwing: CancellationError()) }
    }
}

private final class RenderCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var samples: [Float] = []
    private var rate: Double = 22050
    init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
    func append(_ buffer: AVAudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let continuation, let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            self.continuation = nil
            let count = Int(Double(samples.count) * 16000 / rate)
            guard count > 0, count <= 1_000_000 else { continuation.resume(throwing: CompanionError.unavailable("This reply is too long for pendant audio. Choose iPhone speaker.")); return }
            var result = Data(capacity: count * 2)
            for index in 0..<count {
                let position = Double(index) * rate / 16000; let left = Int(position), right = min(left + 1, samples.count - 1)
                let value = samples[left] + (samples[right] - samples[left]) * Float(position - Double(left))
                var integer = Int16(max(-32767, min(32767, Int(value * 32767)))).littleEndian
                withUnsafeBytes(of: &integer) { result.append(contentsOf: $0) }
            }
            continuation.resume(returning: result); return
        }
        rate = pcm.format.sampleRate
        if let floats = pcm.floatChannelData { samples.append(contentsOf: UnsafeBufferPointer(start: floats[0], count: Int(pcm.frameLength))) }
        else if let ints = pcm.int16ChannelData { samples += UnsafeBufferPointer(start: ints[0], count: Int(pcm.frameLength)).map { Float($0) / 32768 } }
        else { self.continuation = nil; continuation.resume(throwing: CompanionError.unavailable("Unsupported voice audio format.")) }
        if samples.count > 4_000_000 { self.continuation = nil; continuation.resume(throwing: CompanionError.unavailable("Reply audio exceeds the pendant buffer.")) }
    }
}
