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
    /// How many rows show at first, and how many more each time you near the top.
    static let window = 60
    static let more = 30
    /// The most rows on screen while you read back. Older ones come in above and the newest let go
    /// below, so going a long way back stays as light as the start: every row on screen is laid
    /// out, and hundreds of them, with their maps and pictures, made scrolling back hang.
    static let mostShown = 120
    /// How far before the top (or the bottom of what's shown) more comes in, in points.
    static let ahead: CGFloat = 1200

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
        lastShown = nil
    }

    func withoutAnimation(_ change: () -> Void) {
        var settle = Transaction(animation: nil)
        settle.disablesAnimations = true
        withTransaction(settle, change)
    }

    /// Opens the conversation at a row, as from a tapped notification: an older one is shown first,
    /// with the rows around it, since only the latest rows are on screen until you scroll back.
    func open(at id: String, in rows: [Row]) {
        following = false
        if !shownRows(rows).contains(where: { $0.id == id }),
            let index = rows.firstIndex(where: { $0.id == id })
        {
            show(around: index, in: rows)
        }
        Task {
            // A moment for the newly shown rows to be laid out before scrolling to one.
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.4)) { position.scrollTo(id: id, anchor: .top) }
        }
    }

    /// The rows on screen: the latest ones, or from `firstShown` to `lastShown` once you've gone
    /// back. Older rows come in as you near the top (see ``showEarlier(_:)``) and newer ones as you
    /// read back down (``showLater(_:)``); back at the end, it's the latest ones again.
    func shownRows(_ rows: [Row]) -> ArraySlice<Row> {
        guard !rows.isEmpty else { return rows[...] }
        guard let firstShown, let start = cache.index[firstShown] ?? index(of: firstShown, in: rows)
        else { return rows.suffix(Self.window) }
        let end = lastShown.flatMap { cache.index[$0] ?? index(of: $0, in: rows) } ?? rows.count - 1
        return start <= end ? rows[start...end] : rows[start...]
    }

    /// A row's place, for rows the cache hasn't seen yet.
    private func index(of id: String, in rows: [Row]) -> Int? {
        rows.firstIndex { $0.id == id }
    }

    /// Shows a row with a little before it and a window's worth after: the rows around a day or a
    /// topic you jumped to, without laying out everything down to the end first.
    func show(around index: Int, in rows: [Row]) {
        firstShown = rows[max(0, index - 2)].id
        let end = index + Self.window
        lastShown = end >= rows.count - 1 ? nil : rows[end].id
    }

    /// You're nearing the top of what's shown: show more of what Ari has, letting the newest go
    /// below once there are too many, and fetch the page before from the server ahead of time.
    func showEarlier(_ rows: [Row]) {
        let shown = shownRows(rows)
        guard let first = shown.first?.id, let last = shown.last?.id else { return }
        let start = cache.index[first] ?? 0
        if start > 0 {
            reveal(from: max(0, start - Self.more), keepingTo: last, in: rows)
            // Close to the oldest Ari has: the server's page before comes now, not at the top.
            if start - Self.more < Self.more { fetchEarlier(showing: nil) }
            return
        }
        firstShown = first
        fetchEarlier(showing: first)
    }

    /// Shows from `start`, keeping the rows down to `last` but no more than ``mostShown``.
    private func reveal(from start: Int, keepingTo last: String, in rows: [Row]) {
        firstShown = rows[start].id
        let end = cache.index[last] ?? rows.count - 1
        if end - start + 1 > Self.mostShown {
            lastShown = rows[start + Self.mostShown - 1].id
        }
    }

    /// Asks the server for the page before what Ari has. With `showing`, the oldest row shown, some
    /// of the page comes on screen above it as it arrives, keeping your place.
    private func fetchEarlier(showing first: String?) {
        // Only once you've scrolled up: at the end, a short screen would otherwise page back
        // through the whole history by itself.
        guard !following, session.conversation.hasEarlierMessages, !session.isLoadingEarlier
        else { return }
        Task {
            await session.loadEarlier()
            guard let first else { return }
            let now = self.rows(session.conversation)
            guard let index = cache.index[first], index > 0, let last = shownRows(now).last?.id
            else { return }
            reveal(from: max(0, index - Self.more), keepingTo: last, in: now)
        }
    }

    /// You're reading back down from far back: the newer rows come back below, until it reaches
    /// the end and you're following again.
    func showLater(_ rows: [Row]) {
        guard let last = lastShown, let end = cache.index[last] else {
            lastShown = nil
            return
        }
        let next = end + Self.more
        lastShown = next >= rows.count - 1 ? nil : rows[next].id
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
            // Only the rows around it, so there's little to lay out before it lands.
            show(around: index, in: rows)
            // The sheet goes, and the rows are laid out, before scrolling; and once more after,
            // when the rows above have settled their heights.
            try? await Task.sleep(for: .milliseconds(300))
            withoutAnimation { position.scrollTo(id: id, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(150))
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
        // Reading far back, the end of what's shown isn't the end of the conversation.
        guard !following, distanceFromEnd != .atEnd || lastShown != nil else { return nil }
        if working { return "\(LeadName.current) is writing" }
        if repliedWhileAway { return "\(LeadName.current) has replied" }
        return distanceFromEnd == .far || lastShown != nil ? "Latest" : nil
    }
}
