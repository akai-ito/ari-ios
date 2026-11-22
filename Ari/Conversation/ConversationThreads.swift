import AriKit
import SwiftUI

/// Moving a message: the one chosen from its own menu, or none yet, from the thread's ⋯ menu.
struct MoveRequest: Identifiable {
    let id = UUID()
    let chosen: Conversation.Entry?
}

/// Replying, moving and keeping a thread: what you do with threads from the conversation.
extension ConversationView {
    /// In a reply thread, the main chat's message it hangs from: the server's, or for one you're
    /// starting, the message you replied to.
    func anchor(of conversation: Conversation) -> Conversation.Entry? {
        guard let place else { return nil }
        if let anchor = conversation.anchor { return Conversation.Entry(anchor) }
        guard let replied = session.drafts[place] ?? nil else { return nil }
        return session.conversation[replied]
    }

    /// Replying to a message: in the main chat, it opens the thread under it, or starts one; in a
    /// thread, your next message quotes it.
    func reply(to entry: Conversation.Entry) {
        if place == nil {
            openedThread = OpenedThread(id: session.startThread(replyingTo: entry.id))
        } else {
            replyingTo = entry
        }
    }

    /// A message's own actions for threads: reply, and in a thread, move it elsewhere.
    @ViewBuilder
    func threadActions(for entry: Conversation.Entry) -> some View {
        if entry.position != nil {
            Button(
                place == nil ? "Reply in thread" : "Reply",
                systemImage: "arrowshape.turn.up.left"
            ) { reply(to: entry) }
            if place != nil, entry.id != conversation.anchor?.id {
                Button("Move…", systemImage: "arrow.turn.up.right") {
                    moving = MoveRequest(chosen: entry)
                }
            }
        }
    }

    /// The thread's ⋯ menu: done, or open again.
    func markDone(_ isDone: Bool) {
        guard let place else { return }
        Task { try? await session.change(place, ThreadChange(state: isDone ? .done : .open)) }
    }

    func rename(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let place, !trimmed.isEmpty else { return }
        Task { try? await session.change(place, ThreadChange(title: trimmed)) }
    }

    /// Where a message can go, and which messages can go: the main chat and the other open threads.
    func moveSheet(_ request: MoveRequest) -> some View {
        let here = session.resolved(place)
        let movable = conversation.entries.filter { $0.isShown && $0.position != nil }
        return MoveSheet(
            messages: movable.reversed(), chosen: request.chosen,
            destinations: session.conversation.openThreads.filter { $0.id != here },
            isInMainChat: place == nil
        ) { entry, destination in
            Task { try? await session.move(entry.id, to: destination) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ariBackground)
    }
}

extension View {
    /// Swiping a message to the left replies to it, as Messages does; a little give shows it's
    /// coming. Mostly-vertical drags stay the scroll view's.
    func replySwipe(enabled: Bool, reply: @escaping () -> Void) -> some View {
        modifier(ReplySwipe(isEnabled: enabled, reply: reply))
    }
}

private struct ReplySwipe: ViewModifier {
    let isEnabled: Bool
    let reply: () -> Void
    @State private var offset: CGFloat = 0
    @State private var replied = 0

    private static let reach: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .overlay(alignment: .trailing) {
                if offset < -12 {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(offset <= -Self.reach ? Color.ariBone : .ariTertiary)
                        .offset(x: 28)
                        .accessibilityHidden(true)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { drag in
                        guard isEnabled,
                            abs(drag.translation.width) > abs(drag.translation.height) * 2
                        else { return }
                        offset = max(-Self.reach * 1.3, min(0, drag.translation.width))
                    }
                    .onEnded { _ in
                        if offset <= -Self.reach {
                            replied += 1
                            reply()
                        }
                        withAnimation(.spring(duration: 0.25)) { offset = 0 }
                    },
                isEnabled: isEnabled
            )
            .sensoryFeedback(.impact(weight: .light), trigger: replied)
            .accessibilityAction(named: "Reply") { reply() }
    }
}
