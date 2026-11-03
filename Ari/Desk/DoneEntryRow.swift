import AriKit
import SwiftUI

/// One thing Kumo did today, in What I'm up to: what, and why, with Undo where it can be undone and
/// "That was wrong", which opens right under it.
struct DoneEntryRow: View {
    let entry: DoneEntry
    let undo: (DoneEntry) async throws -> Void
    let correct: (DoneEntry, String?) async throws -> Void

    @State private var correcting = false
    @State private var undoing = false
    @State private var problem: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariDusk)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = entry.reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.isCorrected {
                    Text("Noted. I'll do it differently.")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .padding(.top, 2)
                } else if !correcting {
                    actions.padding(.top, 2)
                }
                if let problem { DeskProblemLine(text: problem) }
                if correcting {
                    ThatWasWrong(
                        entry: entry,
                        send: { words in
                            try await correct(entry, words)
                            correcting = false
                        },
                        cancel: { correcting = false }
                    )
                    .padding(.top, 6)
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.smooth(duration: 0.3), value: correcting)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if entry.undo {
                if undoing {
                    ProgressView().controlSize(.small).tint(.ariSecondary)
                        .accessibilityLabel("Undoing")
                } else {
                    Button("Undo") { Task { await performUndo() } }
                        .fontWeight(.semibold)
                        .foregroundStyle(.ariBone)
                        .accessibilityLabel("Undo: \(entry.text)")
                }
            }
            Button("That was wrong") {
                problem = nil
                correcting = true
            }
            .foregroundStyle(.ariTertiary)
            .accessibilityLabel("That was wrong: \(entry.text)")
        }
        .font(.footnote)
        .buttonStyle(.plain)
    }

    private func performUndo() async {
        undoing = true
        problem = nil
        defer { undoing = false }
        do {
            try await undo(entry)
        } catch is CancellationError {
        } catch {
            problem = "Couldn't undo it: \(DeskSending.words(for: error))"
        }
    }
}
