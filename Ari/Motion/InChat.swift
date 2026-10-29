import AriKit
import SwiftUI

/// The pinned line, when there's one to show. Its own view, so the conversation, which redraws
/// with every word of a reply, doesn't follow what's in motion too.
struct PinnedArea: View {
    /// While Ari works on a reply, the line holds as it was, and moves once the reply is on screen:
    /// the words first, then the thing settles.
    let holding: Bool

    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.motionOpener) private var opener
    @State private var held: Pinned?

    struct Pinned: Equatable {
        let motion: Motion
        let detail: MotionDetail?
        let more: Int
    }

    var body: some View {
        let live = motions?.pinned.map {
            Pinned(motion: $0.motion, detail: motions?.details[$0.motion.id], more: $0.more)
        }
        let shown = holding ? held : live
        VStack(spacing: 0) {
            if let motions, let pinned = shown {
                let source = "pinned \(pinned.motion.id)"
                PinnedLine(motion: pinned.motion, detail: pinned.detail, more: pinned.more) {
                    opener.open?(pinned.motion.id, source)
                } dismiss: {
                    withAnimation(.smooth(duration: 0.3)) {
                        held = nil
                        motions.dismiss(pinned.motion)
                    }
                }
                .motionSource(source, in: opener.namespace)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                // It rises from behind the composer with a little spring.
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 34).combined(with: .scale(scale: 0.94)).combined(
                            with: .opacity),
                        removal: .offset(y: 40).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: shown?.motion.id)
        .onChange(of: holding, initial: true) { _, holding in
            if holding { held = live }
        }
    }
}

/// What's in motion, pinned above the composer: one line, where it stands. Tap it to open the
/// thing; drag it down to put it away until Ari next changes it.
struct PinnedLine: View {
    let motion: Motion
    let detail: MotionDetail?
    /// How many more are pinned.
    let more: Int
    let open: () -> Void
    let dismiss: () -> Void

    @State private var drag: CGFloat = 0

    var body: some View {
        let line = MotionLineText(motion, detail)
        Button(action: open) {
            HStack(spacing: 10) {
                SymbolDisc(symbol: MotionSymbol.name(for: motion.kind))
                HStack(spacing: 5) {
                    Text(line.name).fontWeight(.semibold).foregroundStyle(.ariText)
                    Dot()
                    Text(line.detail).foregroundStyle(.ariSecondary)
                    if let left = line.left {
                        Dot()
                        LeftCount(left: left).foregroundStyle(.ariSecondary)
                    }
                    if more > 0 {
                        Dot()
                        Text("+\(more)").foregroundStyle(.ariSecondary)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(.ariSurface, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.ariLine.opacity(0.7))
            )
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .offset(y: max(0, drag))
        .opacity(1 - min(1, max(0, drag) / 120))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 44 || value.predictedEndTranslation.height > 140 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 }
                    }
                }
        )
        .accessibilityLabel(motion.title)
        .accessibilityValue(motion.summary)
        .accessibilityHint("Opens it")
        .accessibilityAction(named: "Put away") { dismiss() }
    }
}

/// The quiet line under a reply when Ari starts or changes a thing in motion: "Started · Florence
/// with Janki", or "Florence with Janki · Booked the Uffizi, 8:15 Saturday". Tap it to open the
/// thing.
struct CompactMotionLine: View {
    let line: ReplyShape.MotionLine

    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.motionOpener) private var opener

    var body: some View {
        let source = "line \(line.motion) \(line.change ?? 0)"
        if let motions, let motion = motions[line.motion] {
            Button {
                opener.open?(motion.id, source)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: MotionSymbol.name(for: motion.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ariBone)
                    Text(text(motion, in: motions))
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .multilineTextAlignment(.leading)
                    if opener.open != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.ariTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.ariLine))
            }
            .buttonStyle(PressStyle())
            .disabled(opener.open == nil)
            .motionSource(source, in: opener.namespace)
            .accessibilityHint(opener.open == nil ? "" : "Opens it")
        } else if motions?.load == .loaded {
            // Forgotten since.
            Text("No longer in motion").font(.footnote).foregroundStyle(.ariTertiary)
        }
    }

    private func text(_ motion: Motion, in motions: Motions) -> String {
        guard let version = line.change, version > 1 else { return "Started · \(motion.title)" }
        guard let note = motions.change(motion.id, version: version)?.note else {
            return motion.title
        }
        return "\(motion.title) · \(note)"
    }
}

/// A quiet dot between the parts of a line.
private struct Dot: View {
    var body: some View {
        Text("·").foregroundStyle(.ariTertiary).accessibilityHidden(true)
    }
}

/// A press you can see: the card dips a little under your finger.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
