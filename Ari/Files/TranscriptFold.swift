import AriKit
import SwiftUI

/// The transcript, folded under Kumo's take: who spoke and for how long, and a tap to open it.
struct TranscriptFold: View {
    let recording: AttachmentID

    @Environment(\.filesActions) private var actions
    @State private var voices: String?

    var body: some View {
        let known = actions.session?.recordings[recording]
        if known?.state != .deleted {
            Button {
                actions.openTranscript(recording, nil)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcript")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.ariText)
                        Text(
                            [voices, known?.durationSeconds.map(durationWords)].compactMap(\.self)
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ariTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                        .ariLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the transcript")
            .task(id: recording) { voices = await Self.voices(of: recording, in: actions.session) }
        }
    }

    /// "You and Lena Okafor", from the voices the server told apart and any names you gave them.
    private static var said: [AttachmentID: String] = [:]

    private static func voices(of recording: AttachmentID, in session: Session?) async -> String? {
        if let kept = said[recording] { return kept }
        guard let transcript = try? await session?.transcript(of: recording) else { return nil }
        let names = transcript.speakers.sorted { $0.seconds > $1.seconds }.map(\.name)
        let words: String? =
            switch names.count {
            case 0: nil
            case 1, 2: names.joined(separator: " and ")
            default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
            }
        said[recording] = words
        return words
    }
}
