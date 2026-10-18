import Foundation
import Combine

@MainActor final class MemoryStore: ObservableObject {
    @Published private(set) var facts: [MemoryFact] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published var persistenceError: String?
    private let file: URL
    private struct Archive: Codable { var facts: [MemoryFact]; var messages: [ChatMessage] }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LittleCompanion", isDirectory: true)
        file = base.appendingPathComponent("memory.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                facts = archive.facts; messages = archive.messages
            }
        } catch { persistenceError = "Saved memory couldn't be opened. The original file has been preserved." }
    }

    @discardableResult func remember(_ text: String) -> Bool {
        // Don't overwrite an unreadable archive with an empty session.
        guard persistenceError == nil else { return false }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return false }
        if let index = facts.firstIndex(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) { facts[index].updated = Date() }
        else { facts.append(MemoryFact(text: trimmed)) }
        return save()
    }
    func forget(_ id: UUID) { facts.removeAll { $0.id == id }; _ = save() }
    func append(_ message: ChatMessage) { messages.append(message); if messages.count > 500 { messages.removeFirst(messages.count - 500) }; _ = save() }
    func clearConversation() { messages.removeAll(); _ = save() }
    func exportData() throws -> Data { try JSONEncoder().encode(Archive(facts: facts, messages: messages)) }
    private func save() -> Bool {
        guard persistenceError == nil else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Archive(facts: facts, messages: messages)).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { persistenceError = "Memory couldn't be saved. Check available storage."; return false }
    }
}
