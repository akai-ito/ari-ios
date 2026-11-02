import AriKit
import SwiftUI

/// "That was wrong" on something Kumo did, opened right under it: one of the usual words in a tap,
/// your own words, or just tell Kumo. Kumo undoes it where it can, keeps what to do differently,
/// and checks with you more for that kind of work.
struct ThatWasWrong: View {
    let entry: DoneEntry
    /// Tells Kumo, with your words or none.
    let send: (String?) async throws -> Void
    let cancel: () -> Void

    @State private var words = ""
    @State private var sending = DeskSending()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let usual = Self.usualWords(for: entry)
            if !usual.isEmpty {
                // On one line when they fit; large text wraps them rather than cutting them off.
                WrappingStack(spacing: 8) {
                    ForEach(usual, id: \.self) { word in
                        DeskPill(
                            title: word, busy: sending.key == word, label: "Tell \(lead): \(word)"
                        ) {
                            tell(word, key: word)
                        }
                        .disabled(sending.isSending)
                    }
                }
            }
            InlineField(
                prompt: "In a word, or more", text: $words,
                button: typed == nil ? "Just tell \(lead)" : "Tell \(lead)", sendsEmpty: true,
                opensKeyboard: true, busy: sending.key == "words", waits: sending.isSending
            ) {
                tell(typed, key: "words")
            }
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(promise)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel That was wrong")
            }
        }
    }

    private var lead: String { LeadName.current }

    private var typed: String? {
        let trimmed = InlineField.trimmed(words)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What happens next, in a line.
    private var promise: String {
        let fix = entry.undo ? "I'll undo it" : "I'll put it right where I can"
        return entry.work == nil
            ? "\(fix) and remember for next time."
            : "\(fix), remember for next time, and check with you more for a while."
    }

    private func tell(_ said: String?, key: String) {
        Task { await sending.send(key) { try await send(said) } }
    }

    /// The usual things wrong with each kind of call, one tap each.
    static func usualWords(for entry: DoneEntry) -> [String] {
        switch entry.work {
        case .sorting?:
            entry.quiet ? ["I needed this", "Not junk"] : ["I needed this", "Wrong folder"]
        case .calendar?: ["Wrong time", "Not for me"]
        case .drafts?: ["No reply needed", "Wrong tone"]
        case .contacts?: ["Wrong person"]
        default: []
        }
    }
}

#if DEBUG
    #Preview("That was wrong") {
        ThatWasWrong(
            entry: DoneEntry(
                id: "d1", at: DeskSamples.at(9, 14),
                text: "Binned \"Your Acme order is on its way\" from Acme",
                reason: "Acme selling something", undo: true, work: .sorting),
            send: { _ in try await Task.sleep(for: .seconds(1)) }, cancel: {}
        )
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
