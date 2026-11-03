import AriKit
import SwiftUI

/// A calendar invitation, held in Kumo's calendar until you answer: what and when, where, what it
/// clashes with, then the card's buttons (Accept, Maybe, Decline). Your tap answers
/// it, and iCloud sends the reply.
struct InviteCardView: View {
    let card: DeskCard
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    @State private var sending = DeskSending()

    var body: some View {
        if let invite = card.invite {
            CardShell(kind: card.kind, context: corner(invite), presentation: presentation) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                    Text(Self.when(invite.event, location: true))
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                    if let line = Self.clashLine(invite) {
                        Text(line).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                CardOptions(card: card, sending: sending, answer: answer)
            }
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }

    /// Where it's held, which matters more than which space it's in.
    private func corner(_ invite: InviteCard) -> String? {
        invite.event.calendar.kumo || invite.event.status == .hold
            ? "held in \(LeadName.current)'s calendar" : context
    }

    /// "Tue 17 Nov · 16:00–17:00 · Zoom", or "Sat 14 Nov · all day".
    static func when(_ event: CalendarItem, location: Bool = false) -> String {
        let day = event.start.date.formatted(DeskTime.weekdayDayMonth)
        let time =
            event.allDay
            ? (DayReading.days(of: event) > 1
                ? "\(DayReading.days(of: event)) days" : "all day")
            : "\(event.start.date.formatted(DeskTime.time))–\(event.end.date.formatted(DeskTime.time))"
        let place = location ? event.location : nil
        return [day, time, place].compactMap(\.self).joined(separator: " · ")
    }

    /// What it clashes with: "Clashes with Parkrun at 09:00."
    static func clashLine(_ invite: InviteCard) -> String? {
        guard let clash = invite.clash else { return nil }
        let at = clash.allDay ? "" : " at \(clash.start.date.formatted(DeskTime.time))"
        return "Clashes with \(clash.title)\(at)."
    }
}

/// Kumo asking: it wasn't sure about something it did, or wants a small decision. The question in
/// Kumo's hand, the card's answers as pills, and room to say something else when words work too.
struct QuestionCardView: View {
    let card: DeskCard
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    @State private var sending = DeskSending()
    @State private var words = ""

    var body: some View {
        if let question = card.question {
            CardShell(kind: card.kind, context: context, presentation: presentation) {
                Text(question.text)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                CardOptions(card: card, sending: sending, answer: answer)
                if card.allowsText { field }
            }
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }

    private var field: some View {
        InlineField(
            prompt: card.options.isEmpty ? "Your answer" : "Or say something else", text: $words,
            buttonLabel: "Send your answer", busy: sending.key == "text",
            waits: sending.isSending || card.isWorking, send: send)
    }

    private func send() {
        let text = InlineField.trimmed(words)
        guard !text.isEmpty else { return }
        Task {
            if await sending.send("text", { try await answer(CardAnswer(text: text)) }) {
                words = ""
            }
        }
    }
}

/// Something Kumo offers, such as a space for Italian or a capability: what, why, and the card's
/// buttons (Accept, Not now). Nothing changes until you accept.
struct OfferCardView: View {
    let card: DeskCard
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    @State private var sending = DeskSending()

    var body: some View {
        if let offer = card.offer {
            CardShell(kind: card.kind, context: context, presentation: presentation) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.text)
                        .font(.ariBody)
                        .foregroundStyle(.ariText)
                        .lineSpacing(Rhythm.ariLineSpacing)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                CardOptions(card: card, sending: sending, answer: answer)
            }
        } else {
            UnknownCardView(card: card, presentation: presentation)
        }
    }
}

/// A card's buttons as pills, wrapping when they don't fit. Each answers with its label; while one
/// is on its way it spins and the rest wait, as they do while the box is working on the card.
struct CardOptions: View {
    let card: DeskCard
    let sending: DeskSending
    let answer: (CardAnswer) async throws -> Void

    var body: some View {
        let buttons = card.options
        if !buttons.isEmpty || card.isWorking || sending.problem != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let said = card.answerWords {
                    // Your answer, then Kumo at work on it: the tap took, and the card leaves once
                    // Kumo has acted, with what followed in Done.
                    DeskAnswerLine(text: said)
                    DeskWorkingLine(text: "\(LeadName.current)'s on it…")
                } else if card.isWorking {
                    DeskWorkingLine()
                }
                if let problem = sending.problem { DeskProblemLine(text: problem) }
                if !buttons.isEmpty, card.answerWords == nil {
                    WrappingStack(spacing: 8) {
                        ForEach(buttons, id: \.label) { button in
                            DeskPill(
                                title: button.label, acts: button.acts,
                                busy: sending.key == button.label
                            ) {
                                Task {
                                    await sending.send(button.label) {
                                        try await answer(CardAnswer(option: button.label))
                                    }
                                }
                            }
                        }
                    }
                    .disabled(sending.isSending || card.isWorking)
                }
            }
            .animation(.smooth(duration: 0.3), value: sending.problem)
            .animation(.smooth(duration: 0.3), value: card.answerWords)
        }
    }
}

#if DEBUG
    #Preview("Invite, question, offer") {
        ScrollView {
            VStack(spacing: 14) {
                InviteCardView(card: DeskSamples.northwindInvite, context: "Career · Job search") {
                    _ in
                    try await Task.sleep(for: .seconds(1))
                }
                QuestionCardView(card: DeskSamples.revolutQuestion) { _ in
                    try await Task.sleep(for: .seconds(1))
                    throw RequestError.network(.notConnectedToInternet)
                }
                OfferCardView(card: DeskSamples.outlookOffer) { _ in
                    try await Task.sleep(for: .seconds(1))
                }
                UnknownCardView(card: DeskSamples.futureCard)
            }
            .padding(16)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
