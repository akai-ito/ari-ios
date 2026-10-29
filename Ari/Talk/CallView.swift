import AriKit
import SwiftUI

/// The call: a calm full screen with Ari large, live captions of both sides, mute and end. It
/// carries on locked and in your pocket; the chevron goes back to the chat while it does.
struct CallView: View {
    let talk: Talk
    let call: CallEngine
    let session: Session

    @State private var poses = PoseHistory(.asking)

    var body: some View {
        VStack(spacing: 0) {
            top
            Spacer(minLength: 24)
            PresenceView(history: poses, size: 132) { call.level.breath() }
                .frame(height: 180)
            // One line at a time: the old one fades out before the new one fades in, so two
            // never read as one.
            ZStack {
                Text(stateLine)
                    .id(stateLine)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.15)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))))
            }
            .font(.subheadline)
            .foregroundStyle(.ariSecondary)
            .padding(.top, 12)
            .animation(.default, value: stateLine)
            Spacer(minLength: 24)
            captions
            Spacer(minLength: 24)
            controls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ariBackground)
        .animation(.easeInOut(duration: 0.3), value: call.phase)
        .animation(.easeInOut(duration: 0.3), value: session.conversation.waitingAsk?.id)
        .onChange(of: pose, initial: true) { _, pose in poses.set(pose) }
    }

    private var top: some View {
        HStack {
            Button {
                talk.showsCall = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.ariSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the chat")
            Spacer()
            VStack(spacing: 2) {
                Text("Ari").font(.headline).foregroundStyle(.ariText)
                if let connected = call.connectedAt {
                    Text(timerInterval: connected...Date.distantFuture, countsDown: false)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.ariTertiary)
                } else {
                    Text("Connecting").font(.caption).foregroundStyle(.ariTertiary)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// Ari's words on top, larger; yours below, live while you talk. What Ari asked, or the
    /// choices its last reply offers, show as buttons as soon as they exist, even while Ari is
    /// still saying them.
    private var captions: some View {
        VStack(spacing: 18) {
            if !call.saying.isEmpty {
                Text(call.saying)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .transition(.opacity)
            }
            if let ask = session.conversation.waitingAsk {
                CallAsk(ask: ask, showsQuestion: call.saying.isEmpty) { option in
                    session.send(option.label)
                }
                .transition(.opacity)
            } else if let choices = latestChoices {
                CallChoices(options: choices) { session.send($0) }
                    .transition(.opacity)
            }
            let yours = call.hearing.isEmpty ? call.lastSaid : call.hearing
            if !yours.isEmpty {
                Text(yours)
                    .font(.callout)
                    .foregroundStyle(call.hearing.isEmpty ? .ariTertiary : .ariSecondary)
                    .transition(.opacity)
            }
            if let problem = call.problem ?? talk.problem {
                Text(problem).font(.footnote).foregroundStyle(.ariSecondary)
            }
            if let diagnostics = call.diagnostics {
                Text(diagnostics)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.ariTertiary)
                    .textSelection(.enabled)
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(6)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
    }

    private var controls: some View {
        HStack(spacing: 56) {
            Button {
                talk.setMuted(!call.muted)
            } label: {
                Image(systemName: call.muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(call.muted ? .ariBackground : .ariText)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(call.muted ? Color.ariText : .clear))
                    .overlay(Circle().strokeBorder(.ariLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(call.muted ? "Unmute" : "Mute")
            Button {
                talk.end()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End call")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: call.muted)
    }

    /// The choices in Ari's latest reply, while it's the last thing said and Ari is idle.
    private var latestChoices: [String]? {
        let conversation = session.conversation
        guard conversation.turn == nil,
            let reply = conversation.entries.last(where: \.isShown), reply.role == .agent,
            reply.endedAt != nil
        else { return nil }
        for shape in ReplyDocument(markdown: reply.text).shapes.values {
            if case .choices(let choices)? = shape { return choices.options }
        }
        return nil
    }

    private var stateLine: String {
        switch call.phase {
        case .connecting: "Getting ready"
        case .listening: call.muted ? "Muted" : call.isHearing ? "Hearing you" : "Listening"
        case .working: session.conversation.turn?.status?.label ?? "Thinking it through"
        case .speaking: "Speaking"
        case .ended: "Call ended"
        }
    }

    private var pose: Pose {
        switch call.phase {
        case .connecting, .ended: .resting
        case .listening: call.isHearing ? .adjusting : .asking
        case .speaking: .writing
        case .working where session.conversation.waitingAsk != nil: .asking
        case .working:
            session.conversation.turn?.status.map { Pose(kind: $0.kind) } ?? .thinking
        }
    }
}

/// What Ari asked, while it waits on a call. Ari says the question and its choices, and saying
/// one answers it; the choices are here too, large, for when tapping is easier than talking.
struct CallAsk: View {
    let ask: Ask
    /// Hidden while Ari is saying it, so it isn't on screen twice.
    var showsQuestion = true
    let answer: (Ask.Option) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if showsQuestion {
                Text(ask.question)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
            }
            if let preview = ask.preview {
                Text(preview)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 10) {
                ForEach(ask.options, id: \.label) { option in
                    CallChoiceButton(
                        label: option.label, detail: option.description, filled: option.acts
                    ) { answer(option) }
                }
            }
            Text(ask.options.isEmpty ? "Say your answer." : "Tap one, or just say it.")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
        }
    }

}

/// A choice on the call screen, as wide as it is, filled when it goes ahead, like Send.
struct CallChoiceButton: View {
    let label: String
    var detail: String?
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.body.weight(filled ? .semibold : .regular))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            .foregroundStyle(filled ? Color.ariBackground : .ariText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background {
                if filled {
                    Capsule().fill(.ariText)
                } else {
                    Capsule().strokeBorder(.ariLine, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The short answers Ari's last reply offers, on the call screen: tap one, or just say it.
struct CallChoices: View {
    let options: [String]
    let choose: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                CallChoiceButton(label: option) { choose(option) }
            }
            Text("Tap one, or just say it.")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
        }
    }
}

/// Why Talk is off, or why the last call ended, in a line above the composer for a few seconds.
struct TalkNotice: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .onTapGesture(perform: dismiss)
            .task(id: text) {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled { dismiss() }
            }
    }
}

/// While a call carries on behind the chat: a quiet bar to go back to it.
struct OnCallBar: View {
    let call: CallEngine
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill").font(.system(size: 12))
                Text(call.phase == .speaking ? "Ari is speaking" : "On a call with Ari")
                Spacer()
                if let connected = call.connectedAt {
                    Text(timerInterval: connected...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(.ariText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.ariSurface))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}
