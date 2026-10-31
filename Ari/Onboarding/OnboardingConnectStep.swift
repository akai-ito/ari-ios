import SwiftUI

/// Step 2: where Kumo can read from, each opening its setup sheet, and whether it's connected. Once
/// anything is, Kumo starts on the last three months and says so. Skip for now is fine: Kumo then
/// starts from what you tell it.
struct OnboardingConnectStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.asking)

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    poses: poses, title: "First, your mail and calendar.",
                    caption:
                        "Kumo reads the last three months to learn what's in motion, then keeps up as new mail comes in. It never sends anything."
                )
                VStack(spacing: 0) {
                    ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                        if index > 0 {
                            Rectangle().fill(Color.ariLine.opacity(0.7)).frame(height: 1)
                                .padding(.leading, 16)
                        }
                        OnboardingSourceRow(source: source) { model.actions.connect(source) }
                    }
                }
                .deskCard(padding: 0)
                if model.anyConnected {
                    OnboardingReadingLine(
                        text: "Kumo has started reading the last three months.",
                        active: !(model.progress?.isDone ?? false)
                    )
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.4), value: model.anyConnected)
        } footer: {
            if model.anyConnected {
                OnboardingButton("Continue") { model.advance() }
            } else {
                OnboardingQuietButton("Skip for now") { model.advance() }
            }
        }
        // Once it has something to read, it reads.
        .onChange(of: model.anyConnected, initial: true) { _, connected in
            poses.set(connected ? .reading : .asking)
        }
    }
}

/// One source: its symbol, name and what it brings, then Connect, or Connected with a bone tick.
/// The whole row opens its setup sheet, to connect or to look at it again.
private struct OnboardingSourceRow: View {
    let source: ConnectableSource
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 28

    var body: some View {
        Button(action: open) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                HStack(spacing: 14) {
                    Image(systemName: source.symbol)
                        .font(.title3)
                        .foregroundStyle(.ariSecondary)
                        .frame(width: symbolWidth)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ariText)
                        Text(source.detail)
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                state
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(source.title), \(source.detail)")
        .accessibilityValue(source.connected ? "Connected" : "Not connected")
        .accessibilityHint(source.connected ? "Shows its setup" : "Sets it up")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var state: some View {
        if source.connected {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.ariBone)
                Text("Connected").foregroundStyle(.ariSecondary)
            }
            .font(.subheadline)
        } else {
            Text("Connect")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
        }
    }
}

#if DEBUG
    #Preview("2 · Connect, one connected") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .connect, connected: ["icloud"],
            progress: OnboardingProgress(read: 120, total: 3100)
        )
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }

    #Preview("2 · Connect, nothing yet") {
        @Previewable @State var model = OnboardingSamples.model(step: .connect, connected: [])
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
