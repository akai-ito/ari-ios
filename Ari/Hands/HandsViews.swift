import AriKit
import SwiftUI
import UIKit

/// The end of a conversation while Kumo's hands are busy in it: its live line, and a one-tap card
/// waiting that no reply of Kumo's holds yet. The times it needed you are in the trail.
struct HandsTail: View {
    let session: Session
    /// The thread, or `nil` for the main chat.
    let place: ThreadID?
    /// Whether the conversation's last row is a trail, which the rail carries on from.
    let followsTrail: Bool

    @Environment(Hands.self) private var hands: Hands?
    @Environment(\.deskItems) private var desk
    @State private var peeking = false

    var body: some View {
        if let hands {
            let line = hands.line(in: place)
            let card = waitingCard(hands)
            if line != nil || card != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if let line {
                        RailRow(
                            dot: .live, breathing: true, starts: !followsTrail, continues: false
                        ) {
                            LiveBrowseLine(line: line, hands: hands) { open(line, hands) }
                        }
                    }
                    if let card {
                        DeskCardView(card: card) { answer in
                            try await desk.answer?(card.id, answer)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheet(isPresented: $peeking) {
                    PeekSheet(hands: hands) {
                        peeking = false
                        Task { await hands.takeOver() }
                    }
                    .presentationDetents([.large])
                    .presentationBackground(Color.ariBackground)
                }
            }
        }
    }

    /// A tap on the line: watch Kumo at work, or take the page when it needs you or is yours.
    private func open(_ line: LiveLine, _ hands: Hands) {
        switch line.kind {
        case .browsing: peeking = true
        case .needsYou, .yours: Task { await hands.takeOver() }
        case .waiting: break
        }
    }

    /// The commit card the browser waits on, here, when no reply here holds it.
    private func waitingCard(_ hands: Hands) -> DeskCard? {
        guard hands.browser.state.shown == .waiting, hands.browser.thread == place,
            let id = hands.browser.card,
            let card = session.desk?.waiting.first(where: { $0.id == id }),
            card.commit?.thread == place
        else { return nil }
        let held = session.conversation(in: place).entries.contains {
            $0.role == .agent && $0.text.contains(id.rawValue)
        }
        return held ? nil : card
    }
}

/// Under a hand-off in the trail: how the page came back, and when.
struct HandoffAnswer: View {
    let handoff: Handoff

    var body: some View {
        if let answered = handoff.answered {
            HStack(spacing: 5) {
                Image(systemName: "hand.point.up.left")
                Text(
                    [answered, handoff.at?.formatted(DeskTime.time)].compactMap(\.self)
                        .joined(separator: " · "))
            }
            .font(.caption)
            .foregroundStyle(.ariTertiary)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Kumo's live line while it browses: where it is and what it's doing, the step it's on, what a tap
/// does, and a small live picture of the page.
struct LiveBrowseLine: View {
    let line: LiveLine
    let hands: Hands
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.text)
                        .font(.footnote)
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: line.text)
                    if let hint = line.hint {
                        HStack(spacing: 4) {
                            Image(systemName: line.kind == .browsing ? "eye" : "hand.point.up.left")
                            Text(hint)
                        }
                        .font(.caption)
                        .foregroundStyle(line.kind == .browsing ? Color.ariTertiary : .ariBone)
                    }
                }
                Spacer(minLength: 4)
                if line.showsPicture {
                    LivePicture(hands: hands, width: 40)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A small live picture of the page, while it's on screen.
struct LivePicture: View {
    let hands: Hands
    let width: CGFloat

    var body: some View {
        let height = width * 2.17
        Group {
            if let data = hands.stream?.picture, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.ariSurface)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(
                Color.ariLine, lineWidth: 1)
        )
        .accessibilityHidden(true)
        .onAppear { hands.watch() }
        .onDisappear { hands.unwatch() }
    }
}

/// Watching Kumo work, live and watch-only: the page shrunk inside a frame (your taps do nothing on
/// it), what Kumo's doing in a line, and Take over.
struct PeekSheet: View {
    let hands: Hands
    let takeOver: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Circle().fill(Color.ariBone).frame(width: 6, height: 6)
                        Text("Watching \(LeadName.current) · live")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariSecondary)
                    Text(hands.browser.site.map { "On \($0)" } ?? "On the web")
                        .font(.ariHeading)
                        .foregroundStyle(.ariText)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.ariText)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            GeometryReader { proxy in
                let page = hands.stream?.view
                let aspect = page.map { CGFloat($0.height) / CGFloat($0.width) } ?? 2.17
                let width = min(proxy.size.width * 0.78, proxy.size.height / aspect)
                Group {
                    if let data = hands.stream?.picture, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Rectangle().fill(Color.ariSurface)
                            ProgressView().tint(.ariSecondary)
                        }
                    }
                }
                .frame(width: width, height: width * aspect, alignment: .top)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.ariLine, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, 16)
            .accessibilityLabel("The page Kumo is on, live")

            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(doing)
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(.ariText)
                    if let step = hands.browser.step {
                        Text("· step \(step)")
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    }
                }
                Button(action: takeOver) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.point.up.left")
                        Text("Take over")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariText)
                    .padding(.horizontal, 26)
                    .frame(height: 46)
                    .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("\(LeadName.current) waits while you have the page")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .onAppear { hands.watch() }
        .onDisappear { hands.unwatch() }
    }

    private var doing: String {
        guard let doing = hands.browser.doing else { return LiveLine(hands.browser)?.text ?? "" }
        return doing.prefix(1).uppercased() + doing.dropFirst()
    }
}
