import AriKit
import SwiftUI

/// What files, recordings and proposed changes can do in the conversation: open a transcript at a
/// moment, and send what a tap says. Equal while it's the same session in the same conversation, so
/// a conversation redrawing every frame as a reply reveals doesn't redraw every card reading it.
struct FilesActions: Equatable {
    var session: Session?
    /// Which conversation on screen opens the transcript. A thread open over the main chat has its
    /// own: equal to the main chat's, SwiftUI kept the main chat's actions in the thread, so its
    /// Transcript fold opened the sheet behind the thread, where it couldn't show.
    var conversation: UUID?
    var openTranscript: (AttachmentID, Double?) -> Void = { _, _ in }

    static func == (a: FilesActions, b: FilesActions) -> Bool {
        a.session === b.session && a.conversation == b.conversation
    }

    /// Sends a tap's message, as if you'd typed its words.
    func send(_ tap: YourTap, saying words: String) {
        session?.send(tap.message(saying: words))
    }
}

extension EnvironmentValues {
    @Entry var filesActions = FilesActions()
}

/// A recording's transcript to open, at a moment or from the start.
struct TranscriptOpening: Identifiable, Equatable {
    let recording: AttachmentID
    let at: Double?
    var id: String { recording.rawValue }
}

extension View {
    /// Files, recordings and Kumo's proposed changes in the chat: a moment Kumo quotes opens the
    /// transcript there, and a tap goes as your message.
    func filesInChat(session: Session) -> some View {
        modifier(FilesInChat(session: session))
    }
}

private struct FilesInChat: ViewModifier {
    let session: Session

    @State private var transcript: TranscriptOpening?
    @State private var conversation = UUID()
    /// The conversation's own way of opening links, for everything but a recording's moments.
    @Environment(\.openURL) private var opensLinks

    func body(content: Content) -> some View {
        let opensLinks = opensLinks
        content
            .environment(
                \.filesActions,
                FilesActions(session: session, conversation: conversation) { recording, at in
                    transcript = TranscriptOpening(recording: recording, at: at)
                }
            )
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let moment = RecordingLink.read(url) else {
                        opensLinks(url)
                        return .handled
                    }
                    transcript = TranscriptOpening(recording: moment.recording, at: moment.seconds)
                    return .handled
                }
            )
            .sheet(item: $transcript) { opening in
                TranscriptSheet(session: session, opening: opening)
                    .presentationDetents([.large])
                    .preferredColorScheme(.dark)
                    .tint(.ariText)
            }
    }
}

// MARK: - Shared pieces

/// A card's button, smaller than the Desk's so two sit beside a line.
struct SmallPill: View {
    let title: String
    var acts = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(acts ? Color.ariBackground : .ariText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if acts {
                        Capsule().fill(Color.ariText)
                    } else {
                        Capsule().strokeBorder(Color.ariLine, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A waveform in dots: bars of bone dots, brighter up to where it's played. Its shape is drawn
/// from the recording's name, not its sound: a mark, not a measurement.
struct DotWaveform: View {
    var played = 0.0
    var bars = 42
    var seed = 0

    var body: some View {
        Canvas { context, size in
            let gap = size.width / CGFloat(bars)
            let dot = min(gap * 0.5, 3)
            let phase = Double(seed % 97) / 10
            for index in 0..<bars {
                let t = Double(index) / Double(bars)
                let wave = abs(sin(t * 19 + phase) * cos(t * 7 + 1 + phase))
                let level = 0.25 + 0.75 * wave * (0.6 + 0.4 * sin(t * 3 + phase))
                let count = max(1, Int(level * Double(size.height / (dot * 1.7))))
                let x = CGFloat(index) * gap + gap / 2
                let color: Color = t < played ? .ariBone : .ariBone.opacity(0.32)
                for k in 0..<count {
                    let offset = (CGFloat(k) - CGFloat(count - 1) / 2) * dot * 1.7
                    let y = size.height / 2 + offset
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                        with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// How long something lasts, as people say it: "52 min", "1 h 5 min", "40 s".
func durationWords(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    if seconds < 60 { return "\(Int(seconds.rounded())) s" }
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
}

/// The same number for the same words on every launch, unlike `hashValue`: a recording's
/// waveform keeps its shape.
func stableSeed(_ words: String) -> Int {
    words.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
}
