import AriKit
import SwiftUI

/// A mail Kumo wrote for you, waiting in your Drafts: who it's to and from, what it's about, the
/// mail itself in a quiet inset, then Change… (words such as "a bit more casual", which rewrite the
/// same draft) and Open in Mail, where you send it. Kumo never sends it itself.
struct DraftCardView: View {
    let card: DeskCard
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sending = DeskSending()
    @State private var changing = false
    @State private var change = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if let draft = card.draft {
            CardShell(kind: card.kind, context: context, presentation: presentation) {
                if presentation == .inline {
                    Text(card.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                }
                fields(draft)
                mail(draft)
                    .opacity(card.isWorking ? 0.5 : 1)
                if card.isWorking {
                    if let said = card.answerWords { DeskAnswerLine(text: said) }
                    DeskWorkingLine(text: "Redrafting…")
                }
                if changing { changeField }
                if let problem = sending.problem { DeskProblemLine(text: problem) }
                buttons(draft)
            }
            .animation(.smooth(duration: 0.3), value: changing)
            .animation(.smooth(duration: 0.3), value: sending.problem)
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }

    /// The mail as it reads in Drafts: its words formatted, your signature quietly under them, then
    /// the pictures and files it carries.
    private func mail(_ draft: DraftCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.formattedBody)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let signature = draft.signature {
                Text(signature)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let attachments = draft.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                        Label(
                            attachment.name,
                            systemImage: attachment.kind == .image ? "photo" : "doc")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariBackground, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The mail: \(draft.plainBody)")
    }

    private func fields(_ draft: DraftCard) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            field("To", draft.to.joined(separator: ", "))
            field("From", draft.from)
            field("Re", draft.subject)
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).font(.footnote).foregroundStyle(.ariTertiary)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// What to change, in your words, sent as a change to the same draft.
    private var changeField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("What should change?", text: $change, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit(sendChange)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ariField, in: .rect(cornerRadius: 16, style: .continuous))
            DeskPill(
                title: "Send", acts: true, busy: sending.key == "change",
                label: "Send the change", action: sendChange
            )
            .disabled(trimmed.isEmpty || sending.isSending || card.isWorking)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    /// Side by side on the right, or one above the other when large text leaves no room.
    private func buttons(_ draft: DraftCard) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                pills(draft)
            }
            VStack(alignment: .trailing, spacing: 8) { pills(draft) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .disabled(sending.isSending || card.isWorking)
    }

    @ViewBuilder
    private func pills(_ draft: DraftCard) -> some View {
        DeskPill(
            title: changing ? "Cancel" : "Change…",
            label: changing ? "Cancel the change" : "Ask \(LeadName.current) to change the draft"
        ) {
            changing.toggle()
            fieldFocused = changing
            if !changing { change = "" }
            sending.clearProblem()
        }
        if let url = Self.mailURL(messageID: draft.messageID) {
            DeskPill(title: "Open in Mail", acts: true, label: "Open the draft in Mail") {
                openURL(url)
            }
        }
    }

    private var trimmed: String { change.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func sendChange() {
        let words = trimmed
        guard !words.isEmpty, !card.isWorking else { return }
        Task {
            let sent = await sending.send("change", failure: "Couldn't send the change") {
                try await answer(CardAnswer(text: words))
            }
            if sent {
                change = ""
                changing = false
            }
        }
    }

    /// Apple Mail's link to a message by its Message-ID: `message://%3C<id>%3E`, the angle
    /// brackets percent-encoded, and anything else a URL can't carry.
    static func mailURL(messageID: String) -> URL? {
        let bare = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard !bare.isEmpty,
            let encoded = bare.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "message://%3C\(encoded)%3E")
    }
}

#if DEBUG
    #Preview("Draft") {
        ScrollView {
            VStack(spacing: 14) {
                DraftCardView(card: DeskSamples.tessDraft, context: "Career · Job search") { _ in
                    try await Task.sleep(for: .seconds(1))
                }
                DraftCardView(card: DeskSamples.hotelDraft, context: "Home & admin · Florence") {
                    _ in
                    try await Task.sleep(for: .seconds(1))
                    throw RequestError.network(.notConnectedToInternet)
                }
            }
            .padding(16)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif

extension DraftCard {
    /// The words as they read in Mail: bold, italics and links drawn, line breaks kept. Words that
    /// aren't valid Markdown show as they are.
    var formattedBody: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    }

    /// The words without their formatting, for previews and VoiceOver.
    var plainBody: String { String(formattedBody.characters) }
}
