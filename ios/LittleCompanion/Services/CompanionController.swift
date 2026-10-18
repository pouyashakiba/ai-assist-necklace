import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor final class CompanionSettings: ObservableObject {
    @Published var name: String { didSet { UserDefaults.standard.set(String(name.prefix(24)), forKey: "companion.name") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "companion.model") } }
    @Published var mode: BrainMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "companion.mode") } }
    @Published var voiceID: String { didSet { UserDefaults.standard.set(voiceID, forKey: "companion.voice") } }
    @Published var pendantSpeaker: Bool { didSet { UserDefaults.standard.set(pendantSpeaker, forKey: "companion.pendantSpeaker") } }
    @Published var speakReplies: Bool { didSet { UserDefaults.standard.set(speakReplies, forKey: "companion.speakReplies") } }
    @Published var cloudEnabled: Bool { didSet { UserDefaults.standard.set(cloudEnabled, forKey: "companion.cloudEnabled") } }
    init() {
        name = UserDefaults.standard.string(forKey: "companion.name") ?? "Milo"
        model = UserDefaults.standard.string(forKey: "companion.model") ?? "gpt-6-astra"
        mode = BrainMode(rawValue: UserDefaults.standard.string(forKey: "companion.mode") ?? "") ?? .automatic
        voiceID = UserDefaults.standard.string(forKey: "companion.voice") ?? ""
        pendantSpeaker = UserDefaults.standard.bool(forKey: "companion.pendantSpeaker")
        speakReplies = UserDefaults.standard.object(forKey: "companion.speakReplies") as? Bool ?? true
        cloudEnabled = UserDefaults.standard.bool(forKey: "companion.cloudEnabled")
    }
}

@MainActor final class CompanionController: ObservableObject {
    let settings = CompanionSettings()
    let memory = MemoryStore()
    let network = Connectivity()
    let speech = SpeechService()
    let pendant = PendantLink()
    let brain = BrainRouter()
    @Published var phase: CompanionPhase = .idle
    @Published var mood: FaceMood = .neutral
    @Published var draft = ""
    @Published var liveWords = ""
    @Published var notice = "Start with a hello. Your companion is ready."
    @Published var handsFree = false
    @Published var lastSource: BrainSource?
    private var turn: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var wakeTimeout: Task<Void, Never>?
    private var wakeTriggered = false
    private var lastUtterance = ""
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    private var turnID = UUID()
    private var subscriptions = Set<AnyCancellable>()

    init() {
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        memory.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        network.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        pendant.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        speech.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        speech.onTranscript = { [weak self] text, final in self?.heard(text, final: final) }
        speech.onFailure = { [weak self] message in
            guard let self, self.phase != .thinking, self.phase != .speaking else { return }
            self.handsFree = false; self.phase = .idle; self.notice = message
        }
        pendant.onWake = { [weak self] in
            guard let self, self.phase != .thinking, self.phase != .speaking else { return }
            self.handsFree = false; self.speech.stopListening(); self.phase = .listening; self.setMood(.listening)
            self.notice = "Pendant awake. Waiting for its text; the iPhone microphone is off."
            self.startCommandTimeout()
        }
        pendant.onText = { [weak self] text, id in
            guard let self, !self.busy, self.turn == nil else { return false }
            self.handsFree = false; self.speech.stopListening(); self.submit(text, deviceRequestID: id); return true
        }
        pendant.onPCM = { [weak self] data in
            guard let self, self.turn == nil else { return }
            self.phase = .thinking
            self.turn = Task { [weak self] in
                guard let self else { return }
                do { let text = try await self.speech.transcribe(pcm: data); self.turn = nil; self.submit(text) }
                catch { self.turn = nil; self.phase = .idle; self.notice = error.localizedDescription }
            }
        }
        pendant.onError = { [weak self] message in self?.notice = message }
        pendant.onPlaybackFinished = { [weak self] in
            guard let self, self.phase == .speaking else { return }
            self.phase = .idle; self.setMood(.happy); if self.handsFree { self.armWakeListener() }
        }
    }

    var busy: Bool { phase == .thinking || phase == .speaking }
    var statusText: String {
        switch phase {
        case .idle: return "A little company, whenever you need it."
        case .waiting: return "Say \(settings.name) to wake me."
        case .listening: return "I'm listening…"
        case .thinking: return "Let me think about that…"
        case .speaking: return "Right here with you."
        }
    }
    func setMood(_ value: FaceMood) { mood = value; pendant.setFace(value) }

    func submit(_ supplied: String? = nil, deviceRequestID: String? = nil) {
        let text = (supplied ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, turn == nil else { return }
        draft = ""; silence?.cancel(); wakeTimeout?.cancel(); speech.stopListening(); liveWords = ""
        let history = memory.messages
        memory.append(ChatMessage(role: "user", text: text))
        phase = .thinking; setMood(.curious)
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Finish companion reply") { [weak self] in
            Task { @MainActor in self?.stop(); self?.notice = "iOS paused the conversation. Open the app to continue." }
        }
        let id = UUID(); turnID = id
        turn = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.turnID == id {
                    self.turn = nil
                    if self.backgroundID != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundID); self.backgroundID = .invalid }
                }
            }
            do {
                let reply: BrainReply
                if let fact = CompanionLogic.rememberedFact(in: text) {
                    guard self.memory.remember(fact) else { throw CompanionError.unavailable(self.memory.persistenceError ?? "Couldn't save this memory.") }
                    reply = BrainReply(text: "I'll remember that: \(fact)", source: .memory)
                } else if text.lowercased().trimmingCharacters(in: .punctuationCharacters) == "what do you remember about me" {
                    reply = BrainReply(text: self.memory.facts.isEmpty ? "I haven't saved any facts yet. You can say, remember that, followed by something you'd like me to keep." : self.memory.facts.suffix(5).map(\.text).joined(separator: ". "), source: .memory)
                } else {
                    if !self.settings.cloudEnabled && self.settings.mode == .cloudOnly { throw CompanionError.unavailable("Cloud is disabled. Choose Automatic or iPhone only.") }
                    reply = try await self.brain.answer(question: text, history: history, facts: self.memory.facts, name: self.settings.name, mode: self.settings.cloudEnabled ? self.settings.mode : .phoneOnly, online: self.network.online, model: self.settings.model)
                }
                try Task.checkCancellation()
                self.memory.append(ChatMessage(role: "assistant", text: reply.text, source: reply.source)); self.lastSource = reply.source
                self.notice = reply.notice ?? "Answered \(reply.source == .cloud ? "with cloud AI" : "on your iPhone")."
                self.setMood(CompanionLogic.mood(for: reply.text))
                if let requestID = deviceRequestID {
                    try await self.pendant.sendReply(reply.text, requestID: requestID, mood: self.mood)
                    if !self.pendant.hardwareAudio { self.phase = .idle; self.notice = "Reply sent to the pendant as text. Pendant audio hardware is not enabled."; return }
                }
                if self.settings.speakReplies {
                    self.phase = .speaking
                    if self.settings.pendantSpeaker || deviceRequestID != nil {
                        let pcm = try await self.speech.renderPCM(reply.text, voiceID: self.settings.voiceID)
                        try Task.checkCancellation(); try await self.pendant.play(pcm: pcm)
                        // Playback-end from the pendant returns to idle. Keep the
                        // voice listener paused so it cannot hear its own reply.
                        return
                    } else { try await self.speech.speak(reply.text, voiceID: self.settings.voiceID) }
                }
                self.phase = .idle
                if self.handsFree { self.armWakeListener() }
            } catch is CancellationError { if self.turnID == id { self.phase = .idle } }
            catch { if self.turnID == id { self.phase = .idle; self.handsFree = false; self.notice = error.localizedDescription; self.setMood(.curious) } }
        }
    }

    func toggleHandsFree() async {
        if handsFree { handsFree = false; speech.stopListening(); phase = .idle; notice = "Wake-name listening is off."; return }
        guard !busy else { return }
        do {
            try await speech.requestPermissions(); handsFree = true; armWakeListener()
            notice = "Listening for \(settings.name). This uses the microphone and battery. Calls or iOS interruptions can stop the session."
        } catch { notice = error.localizedDescription }
    }
    func listenOnce() async {
        guard !busy else { return }
        do {
            try await speech.requestPermissions(); wakeTriggered = false; lastUtterance = ""; liveWords = ""
            phase = .listening; setMood(.listening); try speech.startListening(); startCommandTimeout()
        } catch { phase = .idle; notice = error.localizedDescription }
    }
    private func armWakeListener() {
        guard handsFree else { return }
        do { phase = .waiting; wakeTriggered = false; lastUtterance = ""; liveWords = ""; setMood(.neutral); try speech.startListening() }
        catch { handsFree = false; phase = .idle; notice = error.localizedDescription }
    }
    private func startCommandTimeout() {
        wakeTimeout?.cancel()
        wakeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12)); guard !Task.isCancelled, let self, self.phase == .listening else { return }
            self.speech.stopListening(); self.phase = .idle; self.notice = "I didn't catch a question. Try again."
            if self.handsFree { self.armWakeListener() }
        }
    }
    private func heard(_ text: String, final: Bool) {
        guard phase == .waiting || phase == .listening else { return }
        if phase == .waiting {
            guard let command = CompanionLogic.commandAfterWakeName(settings.name, in: text) else {
                if final, handsFree { armWakeListener() }
                return
            }
            phase = .listening; wakeTriggered = true; setMood(.listening); startCommandTimeout()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            liveWords = command
        } else { liveWords = wakeTriggered ? (CompanionLogic.commandAfterWakeName(settings.name, in: text) ?? text) : text }
        let command = liveWords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { if final { wakeTriggered = false; try? speech.startListening() }; return }
        guard command != lastUtterance || final else { return }; lastUtterance = command
        silence?.cancel()
        silence = Task { [weak self] in
            if !final { try? await Task.sleep(for: .milliseconds(1400)) }
            guard !Task.isCancelled, let self, self.phase == .listening else { return }
            self.submit(command)
        }
    }
    func capturePendant() {
        guard !busy else { return }
        Task {
            do { try await speech.requestPermissions(); speech.stopListening(); phase = .listening; setMood(.listening); try await pendant.requestCapture(); notice = "Recording three seconds on the pendant…" }
            catch { phase = .idle; notice = error.localizedDescription }
        }
    }
    func stop() {
        handsFree = false; turnID = UUID(); turn?.cancel(); turn = nil; silence?.cancel(); wakeTimeout?.cancel()
        speech.stopListening(); speech.stopSpeaking(); pendant.stopPlayback(); phase = .idle; liveWords = ""; setMood(.neutral)
        if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID); backgroundID = .invalid }
    }
}
