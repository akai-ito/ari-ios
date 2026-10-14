import AriKit
import SwiftUI

/// What the status line says.
enum StatusText: Equatable {
    /// A status label, with its detail when it has one: "Searching the web · riverside cafés".
    case status(String, detail: String?)
    /// The agent's note, as its latest sentence.
    case note(String)
    /// Something about the connection or the turn, in Ari's grey: "Reconnecting", "Stopped".
    case quiet(String)

    /// A note's latest sentence: notes can run to several, and the line has room for one.
    static func latestSentence(of note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) {
            sentence, _, _, _ in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespaces)) }
        }
        return sentences.last(where: { !$0.isEmpty }) ?? trimmed
    }

    /// Everything, for VoiceOver.
    var spoken: String {
        switch self {
        case .status(let label, let detail):
            [label, detail].compactMap(\.self).joined(separator: ", ")
        case .note(let note), .quiet(let note): note
        }
    }
}

/// The floating header: the character, "Ari" and one line of status, over the conversation, which
/// scrolls under it and fades out.
struct HeaderView: View {
    let poses: PoseHistory
    let name: String
    let status: StatusText?

    var body: some View {
        VStack(spacing: 2) {
            PresenceView(history: poses)
                .padding(.bottom, 6)
            Text(name)
                .font(.ariName)
                .foregroundStyle(.ariText)
            StatusLine(status: status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background {
            // Solid behind the header, so nothing shows through the status; the conversation
            // fades out just below it.
            VStack(spacing: 0) {
                Color.ariBackground
                LinearGradient(
                    colors: [.ariBackground, .ariBackground.opacity(0)], startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
            }
            .padding(.bottom, -28)
            .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, status?.spoken].compactMap(\.self).joined(separator: ", "))
    }
}

/// One line of live status. It keeps its height when empty, so nothing moves when Ari wakes or
/// rests, and each change fades through.
struct StatusLine: View {
    let status: StatusText?

    var body: some View {
        ZStack {
            Text(" ").hidden()
            if let status {
                line(status)
                    .id(status)
                    .transition(.opacity)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.36), value: status)
    }

    private func line(_ status: StatusText) -> Text {
        switch status {
        case .status(let label, let detail):
            guard let detail else { return Text(label).foregroundStyle(.ariSecondary) }
            return Text(
                "\(Text(label).foregroundStyle(.ariSecondary))\(Text("  ·  ").foregroundStyle(.ariTertiary))\(Text(detail).foregroundStyle(.ariTertiary))"
            )
        case .note(let note):
            return Text(note).font(.ariNote).foregroundStyle(.ariSecondary)
        case .quiet(let text):
            return Text(text).foregroundStyle(.ariTertiary)
        }
    }
}

extension StatusText: Hashable {}
