import SwiftUI

/// Which action the composer's round button is.
enum ComposerRole { case send, stop, idle }

/// The composer: an outlined field and one round button, which is whichever action makes sense
/// now. Send while you have something to send; Stop while Ari works and the field is empty;
/// otherwise Talk, where Ari can take a call, or a dimmed Send. Beside the field, what attaches;
/// above it, what's attached.
struct Composer<Leading: View, Above: View>: View {
    @Binding var draft: String
    let role: Role
    /// What the empty field says: "Message Ari", or "Answer Ari" while Ari waits for you.
    var prompt = "Message Ari"
    /// A secret, such as a code: dots as you type, a key beside them.
    var secret = false
    let send: () -> Void
    let stop: () -> Void
    /// Starts a call, where Ari can take one.
    var talk: (() -> Void)?
    let leading: Leading
    let above: Above

    init(
        draft: Binding<String>, role: ComposerRole, prompt: String = "Message Ari",
        secret: Bool = false, send: @escaping () -> Void, stop: @escaping () -> Void,
        talk: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder above: () -> Above = { EmptyView() }
    ) {
        _draft = draft
        self.role = role
        self.prompt = prompt
        self.secret = secret
        self.send = send
        self.stop = stop
        self.talk = talk
        self.leading = leading()
        self.above = above()
    }

    typealias Role = ComposerRole

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            above
            HStack(alignment: .bottom, spacing: 10) {
                leading
                composerField
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var composerField: some View {
        field
            .foregroundStyle(.ariText)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.ariLine, lineWidth: 1)
            )
            #if os(macOS)
                .onSubmit(send)
            #endif
        let talks = role == .idle && talk != nil
        Button(action: role == .stop ? stop : talks ? talk ?? send : send) {
            ZStack {
                if role == .send {
                    Circle().fill(.ariText)
                } else {
                    Circle().strokeBorder(.ariLine, lineWidth: 1)
                }
                Image(systemName: role == .stop ? "stop.fill" : talks ? "waveform" : "arrow.up")
                    .font(.system(size: role == .stop ? 14 : 18, weight: .bold))
                    .foregroundStyle(talks ? .ariText : glyph)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(role == .idle && !talks)
        .keyboardShortcut(role == .stop ? .cancelAction : .defaultAction)
        .accessibilityLabel(role == .stop ? "Stop" : talks ? "Talk" : "Send")
        .animation(.smooth(duration: 0.3), value: role)
    }

    @ViewBuilder
    private var field: some View {
        if secret {
            HStack(spacing: 8) {
                Image(systemName: "key")
                    .foregroundStyle(.ariTertiary)
                    .accessibilityHidden(true)
                SecureField("", text: $draft, prompt: Text(prompt).foregroundStyle(.ariTertiary))
                    .textFieldStyle(.plain)
                    .textContentType(.oneTimeCode)
                    .onSubmit(send)
            }
        } else {
            TextField(
                "", text: $draft, prompt: Text(prompt).foregroundStyle(.ariTertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...6)
        }
    }

    private var glyph: Color {
        switch role {
        case .send: .ariBackground
        case .stop: .ariText
        case .idle: .ariTertiary
        }
    }
}
