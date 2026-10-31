import SwiftUI

/// Step 1: the character wakes and looks at you, says what it's for in one line, and makes three
/// promises. Under Reduce Motion it's awake and everything is there at once.
struct OnboardingMeetStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.resting)
    /// How much has arrived: the greeting, then each promise, then the button.
    @State private var shown = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let promises: [(symbol: String, text: String)] = [
        ("pencil.line", "I never send anything in your name. I draft; you send."),
        ("lock", "Everything stays on your own box."),
        ("bell", "I tell you only what matters, at a good moment."),
    ]

    var body: some View {
        OnboardingPage(centred: true) {
            VStack(spacing: 36) {
                PresenceView(history: poses, size: 84)
                    .padding(.vertical, 28)
                VStack(spacing: 14) {
                    Text("Hello, I'm Kumo.")
                        .font(.onboardingGreeting)
                        .foregroundStyle(.ariText)
                        .accessibilityAddTraits(.isHeader)
                    Text("I look after the day-to-day, so you don't have to.")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.ariText)
                        .lineSpacing(3)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .onboardingArrival(shown > 0)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(Self.promises.enumerated()), id: \.offset) { index, promise in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Image(systemName: promise.symbol)
                                .font(.body)
                                .foregroundStyle(.ariBone)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(promise.text)
                                .font(.ariBody)
                                .foregroundStyle(.ariText)
                                .lineSpacing(Rhythm.ariLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onboardingArrival(shown > index + 1)
                    }
                }
                .frame(maxWidth: 420)
            }
        } footer: {
            OnboardingButton("Nice to meet you") { model.advance() }
                .onboardingArrival(shown > Self.promises.count + 1)
        }
        .task { await wake() }
    }

    /// The character wakes with a little wiggle, then its words arrive one by one, and it settles
    /// into listening.
    private func wake() async {
        let last = Self.promises.count + 2
        guard !reduceMotion else {
            poses.set(.asking)
            shown = last
            return
        }
        guard shown == 0 else { return }
        try? await Task.sleep(for: .milliseconds(600))
        poses.set(.noticed)
        try? await Task.sleep(for: .milliseconds(650))
        for step in 1...last {
            guard !Task.isCancelled else { break }
            withAnimation(.smooth(duration: 0.7)) { shown = step }
            try? await Task.sleep(for: .milliseconds(step == 1 ? 700 : 260))
        }
        try? await Task.sleep(for: .seconds(1.5))
        poses.set(.asking)
    }
}

#if DEBUG
    #Preview("1 · Meet Kumo") {
        @Previewable @State var model = OnboardingSamples.model(step: .meet, connected: [])
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
