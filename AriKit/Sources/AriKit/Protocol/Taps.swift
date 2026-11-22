import Foundation

/// What a tap on one of Kumo's blocks sends: your message, whose first line says it in words, for the
/// chat and for Kumo, followed by a block saying exactly what you tapped. The chat shows only the
/// words.
public enum YourTap: Sendable, Equatable {
    /// A row of an `ari:proposals` block: make that change, or take it back.
    case decision(Decision)
    /// "Use in draft" on a file Kumo showed: attach that version to the draft it's for.
    case attach(Attach)

    public struct Decision: Sendable, Equatable, Codable {
        /// Kumo's message that holds the block.
        public let message: MessageID
        public let item: String
        public let choice: Choice

        public init(message: MessageID, item: String, choice: Choice) {
            self.message = message
            self.item = item
            self.choice = choice
        }
    }

    public enum Choice: String, Sendable, Equatable, Codable {
        case accept, undo
    }

    public struct Attach: Sendable, Equatable, Codable {
        public let file: FileID
        public let version: Int

        public init(file: FileID, version: Int) {
            self.file = file
            self.version = version
        }
    }

    /// The message to send: the words, then the block.
    public func message(saying words: String) -> String {
        let (kind, json): (String, Data?) =
            switch self {
            case .decision(let decision): ("decision", try? Self.encoder.encode(decision))
            case .attach(let attach): ("attach", try? Self.encoder.encode(attach))
            }
        let body = json.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "\(words)\n\n```ari:\(kind)\n\(body)\n```"
    }

    /// The taps a message of yours carries.
    public static func taps(in text: String) -> [YourTap] {
        guard text.contains("```ari:") else { return [] }
        return blocks(in: text).compactMap { kind, json in
            let data = Data(json.utf8)
            switch kind {
            case "decision":
                return (try? JSONDecoder().decode(Decision.self, from: data)).map(Self.decision)
            case "attach":
                return (try? JSONDecoder().decode(Attach.self, from: data)).map(Self.attach)
            default: return nil
            }
        }
    }

    /// Your words without the blocks a tap added, as the chat shows them.
    public static func words(of text: String) -> String {
        guard text.contains("```ari:") else { return text }
        var kept: [Substring] = []
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !inBlock, line.hasPrefix("```ari:") {
                inBlock = true
            } else if inBlock {
                if line.trimmingCharacters(in: .whitespaces) == "```" { inBlock = false }
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Each `ari:` block in the text: its kind and its JSON.
    private static func blocks(in text: String) -> [(String, String)] {
        var found: [(String, String)] = []
        var kind: String?
        var body: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let open = kind {
                if line.trimmingCharacters(in: .whitespaces) == "```" {
                    found.append((open, body.joined(separator: "\n")))
                    kind = nil
                    body = []
                } else {
                    body.append(line)
                }
            } else if line.hasPrefix("```ari:") {
                kind = String(line.dropFirst("```ari:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return found
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

extension Conversation {
    /// What you've chosen on the proposed changes in Kumo's message `message`: for each row, your
    /// latest decision and the message that carried it, oldest to newest so the last one wins.
    public func decisions(on message: MessageID) -> [String: (
        choice: YourTap.Choice, sent: MessageID
    )] {
        guard let start = entries.firstIndex(where: { $0.id == message }) else { return [:] }
        var decisions: [String: (choice: YourTap.Choice, sent: MessageID)] = [:]
        for entry in entries[start...]
        where entry.role == .user && entry.text.contains("```ari:decision") {
            for case .decision(let decision) in YourTap.taps(in: entry.text)
            where decision.message == message {
                decisions[decision.item] = (decision.choice, entry.id)
            }
        }
        return decisions
    }

    /// Whether Kumo is still on what message `id` asked: it hasn't reached the server, or a turn is
    /// running with no reply from Kumo after it yet.
    public func isWorking(on id: MessageID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        if entries[index].delivery == .sending { return true }
        guard turn != nil else { return false }
        return !entries[index...].contains { $0.role == .agent && $0.kind != .note }
    }
}
