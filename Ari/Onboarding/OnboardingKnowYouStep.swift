import SwiftUI

/// Step 3, while Kumo reads. Someone new gets Kumo's questions, one at a time; someone who comes with
/// memory gets "Here's what I know. Still true?".
struct OnboardingKnowYouStep: View {
    let model: OnboardingModel

    var body: some View {
        if model.knowsYou {
            OnboardingBeliefsStep(model: model)
        } else {
            OnboardingQuestionsStep(model: model)
        }
    }
}

// MARK: - Kumo's questions

/// Kumo asks, in its own hand, one question at a time, each answered by typing or by talking, or
/// skipped. Which question comes next is Kumo's call: it arrives from the box.
private struct OnboardingQuestionsStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.thinking)
    @State private var words = ""
    @State private var sending = DeskSending()

    private var trimmed: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 22) {
                DeskSectionLabel("Getting to know you")
                PresenceView(history: poses, size: 40)
                    .padding(.leading, 2)
                    .padding(.vertical, 8)
                Group {
                    switch model.asking {
                    case .waiting:
                        kumoSays("One moment…", quiet: true)
                    case .asking(let question):
                        VStack(alignment: .leading, spacing: 22) {
                            kumoSays(question.text)
                            answerArea
                        }
                    case .finished:
                        kumoSays(
                            "Thank you. That's plenty to start with; I'll learn the rest as we go.")
                    }
                }
                .id(model.asking)
                .transition(.opacity)
            }
            .animation(.smooth(duration: 0.45), value: model.asking)
        } footer: {
            switch model.asking {
            case .finished:
                OnboardingButton("Continue") { model.advance() }
            case .waiting:
                OnboardingQuietButton("Continue without answering") { model.advance() }
            case .asking:
                EmptyView()
            }
        }
        .onChange(of: pose, initial: true) { _, pose in poses.set(pose) }
        .onChange(of: model.asking) { _, _ in sending.clearProblem() }
    }

    /// Listening while it asks, thinking while your answer goes and the next comes, pleased when
    /// it's done.
    private var pose: Pose {
        if sending.isSending { return .thinking }
        switch model.asking {
        case .waiting: return .thinking
        case .asking: return .asking
        case .finished: return .noticed
        }
    }

    private func kumoSays(_ text: String, quiet: Bool = false) -> some View {
        Text(text)
            .font(.onboardingHeading)
            .foregroundStyle(quiet ? .ariTertiary : .ariText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var answerArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "", text: $words,
                prompt: Text("Type, or talk it through").foregroundStyle(.ariTertiary),
                axis: .vertical
            )
            .font(.body)
            .foregroundStyle(.ariText)
            .lineLimit(3...8)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ariField, in: .rect(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("Your answer")
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            HStack(spacing: 12) {
                Button(action: model.actions.talk) {
                    Label("Talk", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Answer by talking")
                Spacer(minLength: 0)
                Button(action: skip) {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.ariSecondary)
                        .opacity(sending.key == "skip" ? 0 : 1)
                        .overlay {
                            if sending.key == "skip" {
                                ProgressView().controlSize(.small).tint(.ariSecondary)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this question")
                DeskPill(
                    title: "Send", acts: true, busy: sending.key == "answer",
                    label: "Send your answer", action: send
                )
                .disabled(trimmed.isEmpty)
            }
            .disabled(sending.isSending)
        }
    }

    private func send() {
        let text = trimmed
        guard !text.isEmpty else { return }
        Task {
            if await sending.send(
                "answer", failure: "Couldn't send that", { try await model.answer(text) })
            {
                words = ""
            }
        }
    }

    private func skip() {
        Task {
            if await sending.send(
                "skip", failure: "Couldn't skip that", { try await model.skipQuestion() })
            {
                words = ""
            }
        }
    }
}

// MARK: - Still true?

/// For someone who comes with memory: a few things Kumo believes, each Still true or Not any more,
/// with room to say what's true now.
private struct OnboardingBeliefsStep: View {
    let model: OnboardingModel

    @State private var poses = PoseHistory(.asking)

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    poses: poses, title: "Here's what I know. Still true?",
                    caption: "Say what's changed, and Kumo will set things up around it.")
                VStack(spacing: 12) {
                    ForEach(model.beliefs) { belief in
                        OnboardingBeliefRow(model: model, belief: belief)
                    }
                }
            }
        } footer: {
            OnboardingButton("Continue") { model.advance() }
        }
    }
}

/// One belief, in Kumo's hand: Still true, or Not any more and what's true now. Once answered it
/// says so in a line, with Change to answer again.
private struct OnboardingBeliefRow: View {
    let model: OnboardingModel
    let belief: Belief

    @State private var correcting = false
    @State private var words = ""
    @State private var sending = DeskSending()
    @FocusState private var focused: Bool

    var body: some View {
        let reply = model.replies[belief.id]
        VStack(alignment: .leading, spacing: 12) {
            Text(belief.text)
                .font(.ariBody)
                .foregroundStyle(reply == nil ? .ariText : .ariSecondary)
                .lineSpacing(Rhythm.ariLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(reply.map(Self.isCorrection) ?? false, color: .ariTertiary)
            if let problem = sending.problem { DeskProblemLine(text: problem) }
            if let reply {
                answered(reply)
            } else if correcting {
                correction
            } else {
                choices
            }
        }
        .deskCard()
        .animation(.smooth(duration: 0.35), value: reply)
        .animation(.smooth(duration: 0.35), value: correcting)
    }

    private static func isCorrection(_ reply: BeliefReply) -> Bool {
        if case .corrected = reply { true } else { false }
    }

    private var choices: some View {
        WrappingStack(spacing: 8) {
            DeskPill(
                title: "✓ Still true", busy: sending.key == "true", label: "Still true",
                action: confirm)
            DeskPill(title: "Not any more") {
                sending.clearProblem()
                correcting = true
            }
        }
        .disabled(sending.isSending)
    }

    private var correction: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "", text: $words,
                prompt: Text("What's true now? (optional)").foregroundStyle(.ariTertiary),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(.ariText)
            .lineLimit(1...4)
            .focused($focused)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ariField, in: .rect(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("What's true now")
            .onAppear { focused = true }
            HStack(spacing: 8) {
                Button("Cancel") {
                    correcting = false
                    words = ""
                }
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                Spacer(minLength: 0)
                DeskPill(
                    title: "Save", acts: true, busy: sending.key == "correct",
                    label: "Save the correction", action: correct)
            }
            .disabled(sending.isSending)
        }
    }

    private func answered(_ reply: BeliefReply) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch reply {
            case .stillTrue:
                Image(systemName: "checkmark").foregroundStyle(.ariBone)
                Text("Still true").foregroundStyle(.ariSecondary)
            case .corrected(let text):
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.ariBone)
                Text(text.isEmpty ? "Not any more" : text)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Change") {
                correcting = false
                model.reopen(belief)
            }
            .foregroundStyle(.ariTertiary)
            .buttonStyle(.plain)
            .accessibilityLabel("Change your answer")
        }
        .font(.subheadline)
    }

    private func confirm() {
        Task {
            _ = await sending.send("true", failure: "Couldn't save that") {
                try await model.confirm(belief)
            }
        }
    }

    private func correct() {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await sending.send(
                "correct", failure: "Couldn't save that",
                {
                    try await model.correct(belief, to: text)
                })
            {
                correcting = false
                words = ""
            }
        }
    }
}

#if DEBUG
    #Preview("3 · Getting to know you") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .knowYou, connected: ["icloud"],
            progress: OnboardingProgress(read: 1240, total: 3100),
            asking: .asking(OnboardingSamples.questions[0])
        )
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }

    #Preview("3 · Still true? (with memory)") {
        @Previewable @State var model = OnboardingSamples.model(
            step: .knowYou, connected: ["icloud", "outlook"],
            progress: OnboardingProgress(read: 2210, total: 4800),
            beliefs: OnboardingSamples.beliefs
        )
        OnboardingFlow(model: model)
            .preferredColorScheme(.dark)
    }
#endif
