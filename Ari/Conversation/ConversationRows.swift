import AriKit
import Foundation

/// One row of the conversation: a day's date, where the subject changed, your message, Ari's, a
/// trail of what Ari did, a failure that left no reply, or the offer to tell you when Ari's done.
struct ConversationRow: Identifiable {
    enum Kind {
        case day(Date)
        case yours(Conversation.Entry)
        case ari(Conversation.Entry)
        case trail(Trail)
        /// Ari offers to tell you when it's done, once.
        case offer
        /// A turn that failed before writing anything.
        case failure(TurnID, ServerError?)
        /// A call, where it started.
        case call(Call)
        /// Where the subject changed: Ari's label, above the message that changed it.
        case topic(Topic)
    }

    let id: String
    let kind: Kind
}

/// What the conversation screen keeps between frames. A class, so filling it in while drawing
/// doesn't ask SwiftUI to draw again.
final class RowsCache {
    /// What the rows were worked out from: the conversation's changes, where the reveal holds
    /// steps back, and whether Ari offers notifications.
    struct Key: Equatable {
        let revision: Int
        let held: Int?
        let offering: Bool
    }

    var key: Key?
    var rows: [ConversationRow] = []
    private var documents: [MessageID: (text: String, document: ReplyDocument)] = [:]

    /// A reply's Markdown, read once for each text it has.
    func document(_ id: MessageID, _ text: String) -> ReplyDocument {
        if let kept = documents[id], kept.text == text { return kept.document }
        let document = ReplyDocument(markdown: text)
        documents[id] = (text, document)
        return document
    }

    /// The conversation as it reads: messages, Ari's trail between them, the date at the start of
    /// each day, a failure that left no reply, and the notification offer.
    static func make(_ conversation: Conversation, reveal: Reveal, offering: Bool)
        -> [ConversationRow]
    {
        var rows: [ConversationRow] = []
        var day: Date?
        // A topic waits for its message, so a new day's date comes first, then the label.
        var topic: Topic?
        func placeTopic() {
            if let waiting = topic {
                rows.append(ConversationRow(id: "topic \(waiting.id)", kind: .topic(waiting)))
            }
            topic = nil
        }
        for item in Timeline(conversation, reveal: reveal).items {
            guard case .message(let entry) = item else {
                if case .topic(let marked) = item {
                    placeTopic()
                    topic = marked
                    continue
                }
                placeTopic()
                if case .trail(let trail) = item {
                    rows.append(ConversationRow(id: trail.id, kind: .trail(trail)))
                } else if case .call(let call) = item {
                    rows.append(ConversationRow(id: item.id, kind: .call(call)))
                }
                continue
            }
            let date = entry.at?.date ?? .now
            if day.map({ !Calendar.current.isDate($0, inSameDayAs: date) }) ?? true {
                rows.append(ConversationRow(id: "day \(entry.id)", kind: .day(date)))
                day = date
            }
            placeTopic()
            rows.append(
                ConversationRow(
                    id: entry.id.rawValue, kind: entry.role == .user ? .yours(entry) : .ari(entry)))
        }
        if let ended = conversation.lastEndedTurn, ended.outcome == .failed,
            !conversation.entries.contains(where: {
                $0.turn == ended.id && $0.isShown && $0.role == .agent
            })
        {
            rows.append(
                ConversationRow(id: "failure \(ended.id)", kind: .failure(ended.id, ended.error)))
        }
        if offering { rows.append(ConversationRow(id: "offer", kind: .offer)) }
        return rows
    }
}
