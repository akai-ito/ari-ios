import AriKit
import SwiftUI

/// What Kumo would change, each its own row: Skip, or the row's own verb. Nothing is applied until
/// you tap the verb, which tells Kumo to make exactly that change; the row then says what it did,
/// with Undo. Skip stays on this phone, so Kumo never hears about a row you passed on. There's no
/// accepting them all.
struct ProposalsView: View {
    let proposals: ReplyShape.Proposals
    /// Kumo's message that holds them.
    let message: MessageID?

    @Environment(\.filesActions) private var actions
    @AppStorage("skippedProposals") private var skippedText = ""

    var body: some View {
        // Your taps on them are in the same conversation as the card: a thread's, in a thread.
        let conversation = actions.shownConversation
        let decisions = message.flatMap { conversation?.decisions(on: $0) } ?? [:]
        let done = proposals.items.count { decisions[$0.id]?.choice == .accept }
        VStack(alignment: .leading, spacing: 0) {
            DeskSectionLabel(
                proposals.title ?? "What I'd change",
                trailing: done > 0 ? "\(done) of \(proposals.items.count) done" : nil
            )
            .padding(.bottom, 4)
            ForEach(Array(proposals.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.ariLine).frame(height: 1).padding(.leading, 30)
                }
                row(item, state: state(of: item, decisions, conversation))
            }
        }
        .deskCard(padding: 14)
    }

    private enum RowState {
        case open
        case skipped
        /// Accepted; `working` while Kumo is still on it.
        case accepted(working: Bool)
    }

    private func state(
        of item: ReplyShape.Proposals.Item,
        _ decisions: [String: (choice: YourTap.Choice, sent: MessageID)],
        _ conversation: Conversation?
    ) -> RowState {
        if let decision = decisions[item.id], decision.choice == .accept {
            return .accepted(working: conversation?.isWorking(on: decision.sent) ?? false)
        }
        return skipped.contains(key(item)) ? .skipped : .open
    }

    private func row(_ item: ReplyShape.Proposals.Item, state: RowState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Self.symbol(item.kind))
                .font(.subheadline)
                .foregroundStyle(.ariBone)
                .frame(width: 20)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSkipped(state) ? .ariTertiary : .ariText)
                    .fixedSize(horizontal: false, vertical: true)
                switch state {
                case .open:
                    HStack(alignment: .center, spacing: 8) {
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.ariTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        SmallPill(title: "Skip") { skip(item, true) }
                        SmallPill(title: item.verb, acts: true) { decide(item, .accept) }
                            .disabled(actions.session == nil || message == nil)
                    }
                case .skipped:
                    afterLine(
                        Text("Skipped"), undo: { skip(item, false) },
                        label: "Skipped. Undo")
                case .accepted(let working):
                    if working {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(.ariSecondary)
                            Text("\(LeadName.current)'s on it")
                                .font(.caption)
                                .foregroundStyle(.ariSecondary)
                        }
                    } else {
                        afterLine(
                            Text("\(Image(systemName: "checkmark")) \(item.done)"),
                            undo: { decide(item, .undo) }, label: "\(item.done). Undo")
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    /// "✓ Added to your calendar · Undo".
    private func afterLine(_ words: Text, undo: @escaping () -> Void, label: String) -> some View {
        HStack(spacing: 0) {
            words.foregroundStyle(.ariSecondary)
            Text("  ·  ").foregroundStyle(.ariTertiary)
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .foregroundStyle(.ariText)
                .underline()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private func isSkipped(_ state: RowState) -> Bool {
        if case .skipped = state { true } else { false }
    }

    /// Tells Kumo to make that row's change, or take it back: your message says it in words.
    private func decide(_ item: ReplyShape.Proposals.Item, _ choice: YourTap.Choice) {
        guard let message else { return }
        let words = choice == .accept ? "\(item.verb) · \(item.title)" : "Undo · \(item.title)"
        actions.send(
            .decision(YourTap.Decision(message: message, item: item.id, choice: choice)),
            saying: words)
    }

    // MARK: - Skipped, on this phone

    private var skipped: Set<String> {
        Set(skippedText.split(separator: "\n").map(String.init))
    }

    private func key(_ item: ReplyShape.Proposals.Item) -> String {
        "\(message?.rawValue ?? "")/\(item.id)"
    }

    private func skip(_ item: ReplyShape.Proposals.Item, _ skipping: Bool) {
        var keys = skipped
        if skipping { keys.insert(key(item)) } else { keys.remove(key(item)) }
        // The newest few hundred are plenty: old rows have long scrolled away.
        skippedText = keys.sorted().suffix(400).joined(separator: "\n")
    }

    static func symbol(_ kind: String?) -> String {
        switch kind {
        case "calendar": "calendar"
        case "draft": "envelope"
        case "memory": "books.vertical"
        case "desk": "rectangle.stack"
        case "motion": "circle.dotted.circle"
        case "wakeup": "alarm"
        default: "sparkle"
        }
    }
}
