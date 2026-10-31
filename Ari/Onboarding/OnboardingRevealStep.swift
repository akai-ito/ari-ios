import AriKit
import SwiftUI

/// Step 5: what Kumo found. While it's still catching up, a calm wait with how far it's got; then
/// what's in motion in your life, what it added to your calendar, and Open the Desk.
struct OnboardingRevealStep: View {
    let model: OnboardingModel

    var body: some View {
        ZStack {
            if let reveal = model.reveal {
                OnboardingRevealReady(model: model, reveal: reveal)
                    .transition(.opacity)
            } else {
                OnboardingRevealWaiting(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.6), value: model.reveal == nil)
        // Kumo caught up while you waited: a new screen to VoiceOver.
        .onChange(of: model.reveal == nil) { AccessibilityNotification.ScreenChanged().post() }
    }
}

// MARK: - Waiting

/// Kumo still reading: the character with its page, one line in its hand, and the count with a
/// hairline filling. Never a spinner on a blank screen.
private struct OnboardingRevealWaiting: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.reading)

    var body: some View {
        OnboardingPage(centred: true) {
            VStack(spacing: 28) {
                PresenceView(history: poses, size: 64)
                    .padding(.vertical, 24)
                Text(line)
                    .font(.onboardingHeading)
                    .foregroundStyle(.ariText)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let progress = model.progress {
                    OnboardingReadingLine(progress: progress, bar: true, alignment: .center)
                }
            }
        }
        .onChange(of: model.anyConnected, initial: true) { _, connected in
            poses.set(connected ? .reading : .thinking)
        }
    }

    private var line: String {
        model.anyConnected
            ? "Still reading. I'll show you what's in motion once I've caught up."
            : "Thinking over what you told me…"
    }
}

// MARK: - Ready

/// The reveal: Kumo's line, then each thing in motion arriving one by one, then what it added to
/// your calendar, then the button. Under Reduce Motion it's all there at once.
private struct OnboardingRevealReady: View {
    let model: OnboardingModel
    let reveal: OnboardingReveal

    @State private var poses = PoseHistory(.reading)
    /// How many of the pieces have arrived, in order: the heading, the In motion label, each
    /// matter, the calendar's section, the button.
    @State private var shown = 0
    @State private var sending = DeskSending()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mattersStart: Int { 2 }
    private var addedIndex: Int { mattersStart + reveal.matters.count }
    private var buttonIndex: Int { addedIndex + (reveal.added.isEmpty ? 0 : 1) }
    private var pieces: Int { buttonIndex + 1 }

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 30) {
                OnboardingHeader(poses: poses, title: headline)
                    .onboardingArrival(shown > 0)
                if !reveal.matters.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        DeskSectionLabel("In motion")
                            .onboardingArrival(shown > 1)
                        ForEach(Array(reveal.matters.enumerated()), id: \.element.id) { index, matter in
                            OnboardingMatterRow(matter: matter)
                                .onboardingArrival(shown > mattersStart + index)
                        }
                    }
                }
                if !reveal.added.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        DeskSectionLabel("Added to your calendar")
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(reveal.added.enumerated()), id: \.offset) { _, event in
                                OnboardingAddedRow(event: event)
                            }
                        }
                        .deskCard()
                    }
                    .onboardingArrival(shown > addedIndex)
                }
            }
        } footer: {
            Group {
                if let problem = sending.problem { DeskProblemLine(text: problem) }
                OnboardingButton("Open the Desk", busy: sending.isSending, action: finish)
                    .disabled(sending.isSending)
            }
            .onboardingArrival(shown > buttonIndex)
        }
        .task(id: pieces) { await arrive() }
    }

    /// Kumo's line: caught up on your mail, or, with nothing connected, from the talk alone.
    private var headline: String {
        model.anyConnected
            ? "Caught up on three months. Here's what's in motion."
            : "From what you've told me, here's where I'd start."
    }

    /// The pieces arrive one by one, the heading given a moment to itself.
    private func arrive() async {
        guard !reduceMotion else {
            poses.set(.noticed)
            shown = pieces
            return
        }
        if shown == 0 {
            try? await Task.sleep(for: .milliseconds(250))
            poses.set(.noticed)
        }
        while shown < pieces, !Task.isCancelled {
            withAnimation(.smooth(duration: 0.6)) { shown += 1 }
            try? await Task.sleep(for: .milliseconds(shown == 1 ? 800 : 220))
        }
    }

    private func finish() {
        Task {
            await sending.send("finish", failure: "Couldn't open the Desk") {
                try await model.finish()
            }
        }
    }
}

/// Something in motion Kumo found: its symbol, its title and where it stands.
private struct OnboardingMatterRow: View {
    let matter: RevealMatter

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: matter.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ariBackground)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ariBone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(matter.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariText)
                Text(matter.line)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .deskCard()
        .accessibilityElement(children: .combine)
    }
}

/// Something the catch-up put on your calendar.
private struct OnboardingAddedRow: View {
    let event: AddedEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.ariBone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariText)
                Text(event.when)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("5 · Reveal") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .reveal, connected: ["icloud", "outlook"],
            progress: OnboardingProgress(read: 3100, total: 3100), reveal: OnboardingSamples.reveal
        )
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }

    #Preview("5 · Still catching up") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .reveal, connected: ["icloud"],
            progress: OnboardingProgress(read: 2790, total: 3100))
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }

    #Preview("5 · From the talk alone") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .reveal, connected: [], reveal: OnboardingSamples.talkReveal)
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
