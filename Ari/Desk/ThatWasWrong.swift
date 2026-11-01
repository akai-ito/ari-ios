import AriKit
import SwiftUI

/// "That was wrong" on something Kumo did: say what in a word, tap one of the usual words, or just
/// tell Kumo. Kumo undoes it where it can, keeps what to do differently, and checks with you more
/// for that kind of work.
struct ThatWasWrong: View {
    let entry: DoneEntry
    /// Tells Kumo, with your words or none.
    let send: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var sending = DeskSending()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("That was wrong").font(.headline).foregroundStyle(.ariText)
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).font(.subheadline).foregroundStyle(.ariSecondary)
                if let reason = entry.reason {
                    Text(reason).font(.footnote).foregroundStyle(.ariTertiary)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(Color.ariLine).frame(width: 2) }
            .accessibilityElement(children: .combine)
            let usual = Self.usualWords(for: entry)
            if !usual.isEmpty {
                HStack(spacing: 8) {
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
            TextField("In a word, or more", text: $words, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .background(.ariField, in: .rect(cornerRadius: 14, style: .continuous))
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            HStack(alignment: .center, spacing: 12) {
                Text(promise)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                DeskPill(
                    title: typed == nil ? "Just tell \(lead)" : "Tell \(lead)", acts: true,
                    busy: sending.key == "words"
                ) { tell(typed, key: "words") }
                .disabled(sending.isSending)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ariSurface)
    }

    private var lead: String { LeadName.current }

    private var typed: String? {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
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
        Task {
            if await sending.send(key, { try await send(said) }) { dismiss() }
        }
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
        Color.ariBackground
            .sheet(isPresented: .constant(true)) {
                ThatWasWrong(
                    entry: DoneEntry(
                        id: "d1", at: DeskSamples.at(9, 14),
                        text: "Binned \"Your Acme order is on its way\" from Acme",
                        reason: "Acme selling something", undo: true, work: .sorting)
                ) { _ in try await Task.sleep(for: .seconds(1)) }
            }
            .preferredColorScheme(.dark)
    }
#endif
