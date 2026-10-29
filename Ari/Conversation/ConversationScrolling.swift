import AriKit
import SwiftUI

/// Following what arrives, older history as you scroll up, and jumping to a message.
extension ConversationView {
    /// How far you are from the end, in the three bands the screen cares about.
    enum Distance: Equatable {
        /// Within 100 points: following resumes here, even while a reply grows.
        case atEnd
        case near
        /// More than 600 points up: far enough for the Latest pill.
        case far

        init(_ points: CGFloat) {
            self = points < 100 ? .atEnd : points > 600 ? .far : .near
        }
    }

    /// The marker after the last row.
    static let end = "end"
    /// How many rows show at first, and how many more each time you reach the top.
    static let window = 60
    static let more = 40

    func scrollToEnd() {
        follow()
        withAnimation(.smooth(duration: 0.4)) {
            position.scrollTo(id: Self.end, anchor: .bottom)
        }
    }

    func follow() {
        following = true
        repliedWhileAway = false
        // Back at the end, the older rows shown on the way up can go.
        firstShown = nil
    }

    func withoutAnimation(_ change: () -> Void) {
        var settle = Transaction(animation: nil)
        settle.disablesAnimations = true
        withTransaction(settle, change)
    }

    /// Opens the conversation at a row, as from a tapped notification: an older one is shown first,
    /// since only the latest rows are on screen until you scroll back.
    func open(at id: String, in rows: [Row]) {
        following = false
        if !shownRows(rows).contains(where: { $0.id == id }),
            let index = rows.firstIndex(where: { $0.id == id })
        {
            firstShown = rows[max(0, index - 2)].id
        }
        Task {
            // A moment for the newly shown rows to be laid out before scrolling to one.
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.4)) { position.scrollTo(id: id, anchor: .top) }
        }
    }

    /// The rows on screen: the latest ones, from `firstShown` on. More are shown as you scroll up
    /// (see ``showEarlier(_:)``), and the oldest are let go again once you're back at the end.
    func shownRows(_ rows: [Row]) -> ArraySlice<Row> {
        if let firstShown, let start = rows.firstIndex(where: { $0.id == firstShown }) {
            return rows[start...]
        }
        return rows.suffix(Self.window)
    }

    /// You reached the top of what's shown: show more of what Ari has, then ask the server for
    /// what came before.
    func showEarlier(_ rows: [Row]) {
        let first = shownRows(rows).first?.id
        let start = rows.firstIndex(where: { $0.id == first }) ?? 0
        if start > 0 {
            firstShown = rows[max(0, start - Self.more)].id
            return
        }
        firstShown = first
        // Only once you've scrolled up: at the end, a short screen would otherwise page back
        // through the whole history by itself.
        guard !following, session.conversation.hasEarlierMessages, !session.isLoadingEarlier
        else { return }
        Task {
            await session.loadEarlier()
            // The page arrives above what you're reading: show some of it, keeping your place.
            let now = self.rows(session.conversation)
            if let index = now.firstIndex(where: { $0.id == first }), index > 0 {
                firstShown = now[max(0, index - Self.more)].id
            }
        }
    }

    /// Goes to a topic or a day: older history comes in until it's there, then the conversation
    /// opens at it, and settles there once the rows above have their heights.
    func jump(to id: String) {
        following = false
        Task {
            var rows = self.rows(session.conversation)
            while !rows.contains(where: { $0.id == id }), session.conversation.hasEarlierMessages {
                let before = rows.count
                await session.loadEarlier()
                rows = self.rows(session.conversation)
                if rows.count == before { break }
            }
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            firstShown = rows[max(0, index - 2)].id
            // The sheet goes, and the rows are laid out, before scrolling; and once more after,
            // when the rows above have settled their heights.
            try? await Task.sleep(for: .milliseconds(350))
            withoutAnimation { position.scrollTo(id: id, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(200))
            withoutAnimation { position.scrollTo(id: id, anchor: .top) }
        }
    }

    /// Goes to the message at a position, such as where Ari changed a thing in motion: older history
    /// comes in until it reaches that far back, then the conversation opens at it.
    func jump(toPosition position: Int) {
        Task {
            while session.conversation.hasEarlierMessages,
                (session.conversation.entries.first?.position ?? 0) > position
            {
                let before = session.conversation.entries.count
                await session.loadEarlier()
                if session.conversation.entries.count == before { break }
            }
            guard
                let entry = session.conversation.entries.first(where: {
                    ($0.position ?? .max) >= position
                })
            else { return }
            jump(to: entry.id.rawValue)
        }
    }

    func pillText(working: Bool) -> String? {
        guard !following, distanceFromEnd != .atEnd else { return nil }
        if working { return "Ari is writing" }
        if repliedWhileAway { return "Ari has replied" }
        return distanceFromEnd == .far ? "Latest" : nil
    }
}
