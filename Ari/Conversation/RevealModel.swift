import AriKit
import Observation
import SwiftUI

/// The reading pace, shared by the conversation's views without redrawing them all on every frame.
/// Each paced message reads only its own position; the conversation reads only whether anything is
/// still being revealed and where steps wait. Redrawing the whole conversation 30 times a second
/// cost too much once it held more than a few messages.
@MainActor @Observable
final class RevealModel {
    @ObservationIgnored private(set) var reveal = Reveal()
    @ObservationIgnored private var positions: [MessageID: Shown] = [:]
    /// Messages that have ended and are fully on screen: they never move again.
    @ObservationIgnored private var settled: Set<MessageID> = []

    /// Whether anything is still being revealed.
    private(set) var isRevealing = false
    /// Where the first message still being revealed sits: steps after it wait.
    private(set) var held: Int?

    /// How much of one message is on screen, observed by that message alone.
    @MainActor @Observable
    final class Shown {
        fileprivate(set) var position: Double

        init(_ position: Double) {
            self.position = position
        }
    }

    /// The position for `entry`, to read in the view that draws it.
    func shown(_ entry: Conversation.Entry) -> Shown {
        if let kept = positions[entry.id] { return kept }
        let shown = Shown(reveal.position(of: entry))
        positions[entry.id] = shown
        return shown
    }

    /// Moves the reveal on by `elapsed` seconds.
    func advance(by elapsed: TimeInterval, in conversation: Conversation) {
        reveal.advance(by: elapsed, in: conversation)
        sync(conversation)
    }

    /// You tapped Stop: returns the cut (see ``Reveal/stop(in:)``).
    func stop(in conversation: Conversation) -> Cut? {
        let cut = reveal.stop(in: conversation)
        sync(conversation)
        return cut
    }

    /// Brings every position and the coarse state up to date, changing only what changed, so only
    /// the views that depend on it redraw.
    func sync(_ conversation: Conversation) {
        for (id, shown) in positions where !settled.contains(id) {
            guard let entry = conversation[id] else { continue }
            let position = reveal.position(of: entry)
            if position != shown.position { shown.position = position }
            if entry.outcome != nil,
                position >= Double(conversation.visibleText(of: entry).utf16.count)
            {
                settled.insert(id)
            }
        }
        let revealing = reveal.isRevealing(conversation)
        if revealing != isRevealing { isRevealing = revealing }
        let held = Timeline.held(conversation, reveal: reveal)
        if held != self.held { self.held = held }
    }
}

/// Draws a paced message at its position: `.infinity` once it's all on screen. Only this view
/// redraws as the reveal moves on.
struct Paced<Content: View>: View {
    let shown: RevealModel.Shown
    /// The message's visible length, in UTF-16 units.
    let length: Int
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        content(shown.position >= Double(length) ? .infinity : shown.position)
    }
}

/// Moves the reading pace on, 30 times a second while something is being revealed. Its own view, so
/// the frames it runs on don't redraw the conversation.
struct RevealDriver: View {
    let model: RevealModel
    let session: Session

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isRevealing)) {
            context in
            Color.clear.onChange(of: context.date) { previous, now in
                model.advance(
                    by: min(now.timeIntervalSince(previous), 0.1), in: session.conversation)
            }
        }
    }
}
