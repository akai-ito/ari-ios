import AriKit
import SwiftUI

/// Onboarding, right after pairing with the box: meeting Kumo, connecting mail and calendar, Kumo
/// getting to know you while it reads, your morning and notifications, and the reveal of what's in
/// motion. One idea a step, and calm throughout: never a form.
struct OnboardingFlow: View {
    let model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(model: model)
            ZStack {
                page
                    .id(model.step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ariBackground)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.5), value: model.step
        )
        // A new step is a new screen to VoiceOver.
        .onChange(of: model.step) { AccessibilityNotification.ScreenChanged().post() }
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .meet: OnboardingMeetStep(model: model)
        case .connect: OnboardingConnectStep(model: model)
        case .knowYou: OnboardingKnowYouStep(model: model)
        case .morning: OnboardingMorningStep(model: model)
        case .reveal: OnboardingRevealStep(model: model)
        }
    }

    /// The next step rises a little into place as the last fades; under Reduce Motion, a fade.
    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity)
    }
}

/// Back, where there's somewhere to go back to, five small marks for the steps, and, while Kumo
/// reads and you're answering, the quiet line saying how far it's got.
private struct OnboardingTopBar: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                OnboardingStepMarks(step: model.step)
                HStack {
                    if model.step > .meet {
                        Button {
                            model.back()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.ariSecondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        .transition(.opacity)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 10)
            if showsReading, let progress = model.progress {
                OnboardingReadingLine(progress: progress)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: showsReading)
    }

    /// While you answer Kumo, and set up your morning, Kumo is still reading.
    private var showsReading: Bool {
        (model.step == .knowYou || model.step == .morning) && model.reveal == nil
            && model.progress != nil
    }
}

/// Five small marks, the current one longer and in bone, the ones behind it a little lit.
private struct OnboardingStepMarks: View {
    let step: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { each in
                Capsule()
                    .fill(colour(each))
                    .frame(width: each == step ? 18 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.4), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Step \(step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
    }

    private func colour(_ each: OnboardingModel.Step) -> Color {
        if each == step { return .ariBone }
        return each < step ? .ariDusk : .ariLine
    }
}

#if DEBUG
    #Preview("Whole flow") {
        @Previewable @State var model = OnboardingSamples.model(step: .meet, connected: [])
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
