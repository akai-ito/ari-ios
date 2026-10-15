import SwiftUI

/// The composer: an outlined field and one round button, which is whichever action makes sense
/// now. Send while you have text; Stop while Ari works and the field is empty; otherwise a dimmed
/// Send.
struct Composer: View {
    @Binding var draft: String
    let role: Role
    /// What the empty field says: "Message Ari", or "Answer Ari" while Ari waits for you.
    var prompt = "Message Ari"
    /// A secret, such as a code: dots as you type, a key beside them.
    var secret = false
    let send: () -> Void
    let stop: () -> Void

    enum Role { case send, stop, idle }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
            Button(action: role == .stop ? stop : send) {
                ZStack {
                    if role == .send {
                        Circle().fill(.ariText)
                    } else {
                        Circle().strokeBorder(.ariLine, lineWidth: 1)
                    }
                    Image(systemName: role == .stop ? "stop.fill" : "arrow.up")
                        .font(.system(size: role == .stop ? 14 : 18, weight: .bold))
                        .foregroundStyle(glyph)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(role == .idle)
            .keyboardShortcut(role == .stop ? .cancelAction : .defaultAction)
            .accessibilityLabel(role == .stop ? "Stop" : "Send")
            .animation(.smooth(duration: 0.3), value: role)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
