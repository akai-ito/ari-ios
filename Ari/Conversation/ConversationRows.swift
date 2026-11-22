import AriKit
import Foundation

/// One row of the conversation: a day's date, a side thread's line, your message, Ari's, a trail of
/// what Ari did, a failure that left no reply, or the offer to tell you when Ari's done. In a thread,
/// the message it hangs from comes first, and a line saying it's done comes last.
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
        /// A side thread's line in the main chat; `underAnchor` when it hangs from the message above.
        case thread(SideThread, underAnchor: Bool)
        /// The line of a thread you started here, such as with a recording, until the server names
        /// it.
        case startedHere(ThreadID)
        /// In a reply thread: the main chat's message it hangs from.
        case anchor(Conversation.Entry)
        /// At the end of a thread that's done.
        case done(SideThread.Done)
    }

    let id: String
    let kind: Kind
}

/// Where you are in the conversation: the day of what's at the top of the screen.
struct Whereabouts: Equatable {
    let day: Date?
}

/// What the conversation screen keeps between frames. A class, so filling it in while drawing
/// doesn't ask SwiftUI to draw again.
final class RowsCache {
    /// What the rows were worked out from: the conversation's changes, where the reveal holds
    /// steps back, whether Ari offers notifications, and the threads you started that wait for
    /// the server.
    struct Key: Equatable {
        let revision: Int
        let held: Int?
        let offering: Bool
        var waiting: [ThreadID] = []
    }

    var key: Key?
    var rows: [ConversationRow] = []
    /// Each row's place in the conversation, and the subject and day it's under.
    var index: [String: Int] = [:]
    var whereabouts: [String: Whereabouts] = [:]
    private var documents: [MessageID: (text: String, document: ReplyDocument)] = [:]

    /// Keeps `rows`, and works out where each sits.
    func keep(_ rows: [ConversationRow], for key: Key) {
        self.key = key
        self.rows = rows
        index = [:]
        whereabouts = [:]
        var day: Date?
        for (position, row) in rows.enumerated() {
            if case .day(let date) = row.kind { day = date }
            index[row.id] = position
            whereabouts[row.id] = Whereabouts(day: day)
        }
    }

    /// The topmost of the rows on screen.
    func topmost(of ids: [String]) -> String? {
        ids.min { (index[$0] ?? .max) < (index[$1] ?? .max) }
    }

    /// A reply's Markdown, read once for each text it has.
    func document(_ id: MessageID, _ text: String) -> ReplyDocument {
        if let kept = documents[id], kept.text == text { return kept.document }
        let document = ReplyDocument(markdown: text)
        documents[id] = (text, document)
        return document
    }

    /// The conversation as it reads: messages, Ari's trail between them, the date at the start of
    /// each day, the threads you started that wait for the server, a failure that left no reply,
    /// and the notification offer.
    static func make(
        _ conversation: Conversation, reveal: Reveal, offering: Bool,
        anchor: Conversation.Entry? = nil, waiting: [ThreadID] = []
    ) -> [ConversationRow] {
        var rows: [ConversationRow] = []
        var day: Date?
        if let anchor {
            rows.append(ConversationRow(id: "anchor \(anchor.id)", kind: .anchor(anchor)))
        }
        var above: MessageID?
        for item in Timeline(conversation, reveal: reveal).items {
            guard case .message(let entry) = item else {
                if case .thread(let thread) = item {
                    let isUnder = thread.anchor != nil && thread.anchor == above
                    rows.append(
                        ConversationRow(id: item.id, kind: .thread(thread, underAnchor: isUnder)))
                    continue
                }
                above = nil
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
            rows.append(
                ConversationRow(
                    id: entry.id.rawValue, kind: entry.role == .user ? .yours(entry) : .ari(entry)))
            above = entry.id
        }
        for thread in waiting {
            rows.append(ConversationRow(id: "started \(thread)", kind: .startedHere(thread)))
        }
        if let ended = conversation.lastEndedTurn, ended.outcome == .failed,
            !conversation.entries.contains(where: {
                $0.turn == ended.id && $0.isShown && $0.role == .agent
            })
        {
            rows.append(
                ConversationRow(id: "failure \(ended.id)", kind: .failure(ended.id, ended.error)))
        }
        if let done = conversation.thread?.done {
            rows.append(ConversationRow(id: "done \(done.at.rawValue)", kind: .done(done)))
        }
        if offering { rows.append(ConversationRow(id: "offer", kind: .offer)) }
        return rows
    }
}
