import Foundation

enum BrainMode: String, Codable, CaseIterable, Identifiable {
    case automatic, phoneOnly, cloudOnly
    var id: String { rawValue }
    var title: String { switch self { case .automatic: return "Automatic"; case .phoneOnly: return "iPhone only"; case .cloudOnly: return "Cloud only" } }
}

enum BrainSource: String, Codable { case phone = "On iPhone", cloud = "Cloud AI", memory = "Memory", device = "Pendant" }
enum CompanionPhase: String { case idle, waiting, listening, thinking, speaking }
enum FaceMood: String, Codable, CaseIterable, Identifiable {
    case neutral, happy, laughing, shy, curious, surprised, sleepy, sleeping, affectionate, playful, sad, listening
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String
    let text: String
    let source: BrainSource?
    let date: Date
    init(role: String, text: String, source: BrainSource? = nil) {
        self.id = UUID(); self.role = role; self.text = text; self.source = source; self.date = Date()
    }
}

struct MemoryFact: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var updated = Date()
}

struct BrainReply {
    let text: String
    let source: BrainSource
    var notice: String? = nil
}

enum CompanionError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case cloud(Int)
    case disconnected
    case cancelled
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidResponse: return "The AI returned an incomplete response. Please try again."
        case .cloud(let code): return "Cloud request failed (HTTP \(code)). Check your API key, model access, and API billing."
        case .disconnected: return "Connect your pendant first."
        case .cancelled: return "The conversation was stopped."
        }
    }
}

enum CompanionLogic {
    static func rememberedFact(in text: String) -> String? {
        let prefixes = ["remember that ", "remember this: ", "remember: "]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix) {
            let fact = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return fact.isEmpty ? nil : String(fact.prefix(500))
        }
        return nil
    }

    // Match complete words, so Milo doesn't activate inside "Camilo".
    static func commandAfterWakeName(_ name: String, in transcript: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)),
              let range = Range(match.range, in: transcript) else { return nil }
        return String(transcript[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func mood(for text: String) -> FaceMood {
        let lower = text.lowercased()
        if lower.contains("sorry") || lower.contains("sad") { return .sad }
        if lower.contains("love") || lower.contains("care about") { return .affectionate }
        if lower.contains("haha") || lower.contains("joke") { return .playful }
        if lower.contains("wow") { return .surprised }
        if lower.contains("good night") { return .sleepy }
        return .happy
    }

    static func shouldUseCloud(mode: BrainMode, online: Bool, hasKey: Bool) -> Bool {
        switch mode { case .phoneOnly: return false; case .cloudOnly: return true; case .automatic: return online && hasKey }
    }

    static func memoryContext(_ facts: [MemoryFact], question: String, limit: Int = 10) -> String {
        let words = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 }.map(String.init))
        let ranked = facts.enumerated().sorted { a, b in
            let scoreA = words.filter { a.element.text.lowercased().contains($0) }.count
            let scoreB = words.filter { b.element.text.lowercased().contains($0) }.count
            return scoreA == scoreB ? a.element.updated > b.element.updated : scoreA > scoreB
        }
        return ranked.prefix(limit).map { "- " + $0.element.text }.joined(separator: "\n")
    }
}
