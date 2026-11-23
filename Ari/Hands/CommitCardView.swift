import AriKit
import SwiftUI
import UIKit

/// The one-tap card for something free: a still of the final page (tap it to see it whole), what it
/// books in a line, where and as of when, and the site's own verb. It's bound to that page as it
/// was: the box presses the button only if the page is still the same. Once you've pressed it, it
/// keeps the still and says so.
struct CommitCardView: View {
    let card: DeskCard
    var context: String?
    var presentation = CardPresentation.card
    /// Where it stands; from the card itself while it waits.
    var state: CommitState?
    let answer: (CardAnswer) async throws -> Void

    @Environment(\.attachmentBytes) private var bytes
    @Environment(Hands.self) private var hands: Hands?
    @State private var sending = DeskSending()
    @State private var changing = false
    @State private var change = ""
    @State private var still: UIImage?
    @State private var showsStill = false

    var body: some View {
        if let commit = card.commit {
            switch presentation {
            case .card:
                VStack(alignment: .leading, spacing: 12) {
                    header(commit)
                    content(commit)
                }
                .deskCard()
            case .inline:
                CardShell(kind: card.kind, presentation: .inline) {
                    content(commit)
                }
            }
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }

    private var shown: CommitState {
        if let state { return state }
        return card.isWorking || card.answerWords != nil ? .booking : .ready
    }

    private var isDone: Bool {
        switch shown {
        case .pressed, .done: true
        default: false
        }
    }

    /// The option that presses the site's button, such as "Book".
    private var acting: Ask.Option? { card.options.first(where: \.acts) }

    private func header(_ commit: CommitCard) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(
                isDone ? doneWord : "Ready to \((acting?.label ?? commit.button).lowercased())",
                systemImage: isDone ? "checkmark" : "hand.tap"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDone ? Color.ariSecondary : .ariBone)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(corner(commit))
                .font(.caption)
                .foregroundStyle(.ariTertiary)
                .lineLimit(1)
        }
    }

    private var doneWord: String {
        if case .done = shown { return "Booked" }
        return "Pressed"
    }

    /// "Tablewise · as of 16:45", or once pressed, when.
    private func corner(_ commit: CommitCard) -> String {
        switch shown {
        case .pressed(let at), .done(_, let at):
            return "\(commit.site) · \(at.formatted(DeskTime.time))"
        default:
            let asOf = (card.changedAt ?? card.at).date.formatted(DeskTime.time)
            return "\(commit.site) · as of \(asOf)"
        }
    }

    private func content(_ commit: CommitCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.ariName).foregroundStyle(.ariText)
                    Text(commit.summary)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let details = Self.details(commit) {
                        Text(details)
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    outcome(commit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            if changing {
                InlineField(
                    prompt: "What should change?", text: $change,
                    buttonLabel: "Tell \(LeadName.current) what to change", opensKeyboard: true,
                    busy: sending.key == "change", waits: sending.isSending || card.isWorking,
                    send: sendChange)
            }
            if let problem = sending.problem { DeskProblemLine(text: problem) }
        }
        .task(id: commit.screenshot) {
            guard still == nil, let data = await bytes?(commit.screenshot) else { return }
            still = UIImage(data: data)
        }
        .sheet(isPresented: $showsStill) {
            StillSheet(image: still, site: commit.site)
        }
    }

    private var thumbnail: some View {
        Button {
            if still != nil { showsStill = true }
        } label: {
            Group {
                if let still {
                    Image(uiImage: still).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.ariSurface)
                }
            }
            .frame(width: 76, height: 150, alignment: .top)
            .clipShape(.rect(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.ariLine, lineWidth: 1)
            )
            .opacity(isDone ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("The page as \(LeadName.current) left it")
        .accessibilityHint("Shows it whole")
    }

    @ViewBuilder
    private func outcome(_ commit: CommitCard) -> some View {
        switch shown {
        case .done(let reference, _):
            Label(
                "You booked it" + (reference.map { " · ref \($0)" } ?? ""),
                systemImage: "checkmark"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.ariSecondary)
        case .pressed:
            Label("You pressed \(acting?.label ?? commit.button)", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ariSecondary)
        case .changed:
            Text(
                "The page changed, so nothing was pressed. \(LeadName.current) is looking again."
            )
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .fixedSize(horizontal: false, vertical: true)
        case .ready, .booking:
            if let said = card.answerWords, acting?.label != said {
                DeskAnswerLine(text: said)
            }
            HStack(spacing: 8) {
                ForEach(card.options.filter { !$0.acts }, id: \.label) { option in
                    DeskPill(
                        title: changing ? "Cancel" : option.label,
                        busy: sending.key == option.label
                    ) {
                        other(option)
                    }
                }
                if let acting {
                    DeskPill(
                        title: acting.label, acts: true,
                        busy: sending.key == acting.label || shown == .booking
                    ) {
                        press(acting)
                    }
                }
            }
            .disabled(sending.isSending || shown == .booking)
        }
    }

    /// "Window counter · free to cancel until Fri 19:30".
    static func details(_ commit: CommitCard) -> String? {
        guard let details = commit.details, !details.isEmpty else { return nil }
        return details.map(\.value).joined(separator: " · ")
    }

    private func press(_ option: Ask.Option) {
        Task {
            await sending.send(option.label) {
                try await answer(CardAnswer(option: option.label))
            }
        }
    }

    /// The other option: one that asks for words ("Change…") opens a field when words work as an
    /// answer; otherwise it goes as it is. Either way nothing is pressed: Kumo hears it.
    private func other(_ option: Ask.Option) {
        if card.allowsText, option.label.hasSuffix("…") {
            changing.toggle()
            if !changing { change = "" }
            sending.clearProblem()
            return
        }
        Task {
            await sending.send(option.label) {
                try await answer(CardAnswer(option: option.label))
            }
        }
    }

    private func sendChange() {
        let words = InlineField.trimmed(change)
        guard !words.isEmpty else { return }
        Task {
            let sent = await sending.send("change") { try await answer(CardAnswer(text: words)) }
            if sent {
                changing = false
                change = ""
            }
        }
    }
}

/// The page as Kumo left it, whole, with the button outlined.
private struct StillSheet: View {
    let image: UIImage?
    let site: String

    var body: some View {
        ScrollView {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .padding(20)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.ariBackground)
        .accessibilityLabel("The page on \(site) as Kumo left it")
    }
}
