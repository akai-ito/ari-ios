import AriKit
import SwiftUI

/// What the status line says.
enum StatusText: Equatable {
    /// A status label, with its detail when it has one: "Searching the web · riverside cafés".
    case status(String, detail: String?)
    /// Something about the connection or the turn, in Ari's grey: "Reconnecting", "Stopped".
    case quiet(String)

    /// Everything, for VoiceOver.
    var spoken: String {
        switch self {
        case .status(let label, let detail):
            [label, detail].compactMap(\.self).joined(separator: ", ")
        case .quiet(let text): text
        }
    }
}

/// The floating header: the character, where you are, and one line of status, over the
/// conversation, which scrolls under it and fades out. Where you are is the day of what's at the top
/// of the screen, changing as you scroll; tap it for Threads by day. Resting, the line under it says
/// how many threads are open. The character is Ari, so it needs no name. Tap it and it notices you.
struct HeaderView: View {
    /// Read here rather than by the conversation, so the header redrawing as you scroll, or as a
    /// status changes, doesn't redraw the whole conversation.
    let header: HeaderState
    /// For VoiceOver, and the title before there's anything said.
    let name: String
    /// How many side threads are open, for the quiet line while Kumo rests.
    var openThreads = 0
    /// Opens Threads by day.
    var openTopics: (() -> Void)?
    /// You tapped the character.
    var nudge: (() -> Void)?

    var body: some View {
        let whereabouts = header.whereabouts
        let day = whereabouts?.day.map { DayLabel.describe($0, time: false) }
        let title = day ?? name
        // Working, the status; resting, how many threads are open.
        let threads = openThreads == 1 ? "1 open thread" : "\(openThreads) open threads"
        let status = header.status ?? (openThreads > 0 ? .quiet(threads) : nil)
        VStack(spacing: 2) {
            PresenceView(history: header.poses)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
                .onTapGesture { nudge?() }
                .sensoryFeedback(
                    .impact(weight: .light, intensity: 0.6),
                    trigger: header.poses.current == .noticed)
            Button {
                openTopics?()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .font(.ariName)
                        .foregroundStyle(.ariText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.ariTertiary)
                }
                .padding(.horizontal, 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(openTopics == nil)
            .animation(.easeInOut(duration: 0.3), value: title)
            // A quiet turn's line gains how long it's been going, a tick at a time.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                StatusLine(status: header.clocked(status, at: context.date))
            }
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
        .accessibilityLabel(
            [name, title == name ? nil : title, header.clocked(status, at: .now)?.spoken]
                .compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(openTopics == nil ? "" : "Shows your threads by day")
        .accessibilityAction { openTopics?() }
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
                // The old line leaves quickly before the new one arrives, so two long ones
                // never sit on top of each other.
                line(status)
                    .id(status)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.28).delay(0.1)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))))
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
        case .quiet(let text):
            return Text(text).foregroundStyle(.ariTertiary)
        }
    }
}

extension StatusText: Hashable {}
