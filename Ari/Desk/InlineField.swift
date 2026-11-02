import SwiftUI

/// Words for Kumo, typed right where you are: a field that grows to a few lines, with its button
/// beside it. It opens with the keyboard when it appears in answer to a tap (Reply, Something
/// else…, That was wrong, Change…), and stays put on a card that always takes words. With the
/// largest text, the button goes under the field rather than squeezing it.
struct InlineField: View {
    let prompt: String
    @Binding var text: String
    /// The button: Send, or what it does, such as "Tell Kumo".
    var button = "Send"
    /// What VoiceOver says for the button, when its title alone isn't enough.
    var buttonLabel: String?
    /// Whether the button goes ahead with nothing typed, such as "Just tell Kumo".
    var sendsEmpty = false
    /// Whether the field opens with the keyboard.
    var opensKeyboard = false
    /// The longest answer it takes, in characters.
    var limit: Int?
    var busy = false
    /// Whether it can't send just now, such as while the box works on the card.
    var waits = false
    let send: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        layout {
            TextField(prompt, text: $text, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSend { send() } }
                .onChange(of: text) { _, words in
                    if let limit, words.count > limit { text = String(words.prefix(limit)) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ariField, in: .rect(cornerRadius: 16, style: .continuous))
            DeskPill(title: button, acts: true, busy: busy, label: buttonLabel, action: send)
                .disabled(!canSend)
        }
        .onAppear { if opensKeyboard { focused = true } }
    }

    private var canSend: Bool {
        !busy && !waits && (sendsEmpty || !Self.trimmed(text).isEmpty)
    }

    /// The words without the space around them.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
    #Preview("Inline field") {
        @Previewable @State var words = ""
        VStack(spacing: 16) {
            InlineField(prompt: "Your answer", text: $words) {}
            InlineField(
                prompt: "In a word, or more", text: $words, button: "Just tell Kumo",
                sendsEmpty: true
            ) {}
        }
        .padding(18)
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
