import AriKit
import SwiftUI

/// How a card is drawn: on its own, framed with its kind on top, or inline in the Desk's Waiting on
/// you, beside its kind's symbol and sharing one frame with the cards around it.
enum CardPresentation {
    case card
    case inline
}

/// Something waiting on you, drawn as its kind. A kind Ari doesn't know, or a card missing its
/// kind's part, shows its title and nothing to tap.
struct DeskCardView: View {
    let card: DeskCard
    /// Where it belongs, for the corner of its header, such as "Career · Job search".
    var context: String?
    var presentation = CardPresentation.card
    let answer: (CardAnswer) async throws -> Void

    var body: some View {
        switch card.kind {
        case .draft:
            DraftCardView(card: card, context: context, presentation: presentation, answer: answer)
        case .invite:
            InviteCardView(card: card, context: context, presentation: presentation, answer: answer)
        case .times:
            TimesCardView(card: card, context: context, presentation: presentation, answer: answer)
        case .question:
            QuestionCardView(
                card: card, context: context, presentation: presentation, answer: answer)
        case .offer:
            OfferCardView(card: card, context: context, presentation: presentation, answer: answer)
        default:
            UnknownCardView(card: card, presentation: presentation)
        }
    }
}

/// What every card shares: its kind's name and symbol, and its frame on its own.
struct CardShell<Content: View>: View {
    let kind: CardKind
    var context: String?
    let presentation: CardPresentation
    @ViewBuilder let content: Content

    var body: some View {
        switch presentation {
        case .card:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(CardLook.name(kind), systemImage: CardLook.symbol(kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ariBone)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let context {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                            .lineLimit(1)
                    }
                }
                content
            }
            .deskCard()
        case .inline:
            HStack(alignment: .top, spacing: 12) {
                CardSymbol(kind: kind)
                VStack(alignment: .leading, spacing: 10) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A card kind's symbol, in bone, in the Desk list's column.
struct CardSymbol: View {
    let kind: CardKind

    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 22

    var body: some View {
        Image(systemName: CardLook.symbol(kind))
            .font(.body.weight(kind == .question ? .semibold : .regular))
            .foregroundStyle(.ariBone)
            .frame(width: width)
            .accessibilityLabel(CardLook.name(kind))
    }
}

/// A card this version of Ari can't draw: its title, and nothing to tap.
struct UnknownCardView: View {
    let card: DeskCard
    var presentation = CardPresentation.card

    var body: some View {
        CardShell(kind: card.kind, presentation: presentation) {
            Text(card.title)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A card folded to one row for the Desk: "Draft to Hotel Orto", the first line of the mail, and a
/// chevron that opens it in full. A kind Ari doesn't know is its title alone, with nothing to tap.
struct DeskCardRow: View {
    let card: DeskCard
    let open: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        if card.kind.isKnown {
            Button(action: open) {
                content(chevron: true).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens it")
        } else {
            content(chevron: false).accessibilityElement(children: .combine)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            CardSymbol(kind: card.kind)
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                if let detail = Self.detail(card) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var titleLine: Text {
        let title = Text(card.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
        guard let since = Self.since(card.at.date, calendar: calendar) else { return title }
        return Text(
            "\(title)\(Text("  ·  \(since)").font(.footnote).foregroundStyle(.ariTertiary))")
    }

    /// The row's second line: the mail's first words, what the times are for, when the event is.
    static func detail(_ card: DeskCard) -> String? {
        switch card.kind {
        case .draft:
            guard let body = card.draft?.body else { return nil }
            let first = body.split(whereSeparator: \.isNewline).first {
                !$0.allSatisfy(\.isWhitespace)
            }
            return first.map { "“\($0.trimmingCharacters(in: .whitespaces))”" }
        case .times:
            guard let times = card.times else { return nil }
            let count = times.slots.count == 1 ? "1 time" : "\(times.slots.count) times"
            return "\(times.purpose) · \(count) to check"
        case .invite:
            guard let event = card.invite?.event else { return nil }
            return InviteCardView.when(event)
        case .question: return card.question?.text
        case .offer: return card.offer?.text
        default: return nil
        }
    }

    /// "since Wed" for a card from before today; nothing for today's.
    static func since(_ date: Date, now: Date = .now, calendar: Calendar) -> String? {
        let today = calendar.startOfDay(for: now)
        guard date < today else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today)
        if (days.day ?? 0) < 7 {
            return "since \(date.formatted(.dateTime.weekday(.abbreviated)))"
        }
        return "since \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// Waiting on you, as the Desk shows it: one frame, drafts and times folded to rows that open in
/// full, and invites, questions and offers in full where they are, to answer in a tap.
struct WaitingList: View {
    let cards: [DeskCard]
    /// Where each card belongs, such as "Career · Job search".
    var context: (DeskCard) -> String? = { _ in nil }
    /// Opens a folded card in full.
    let open: (DeskCard) -> Void
    let answer: (DeskCard, CardAnswer) async throws -> Void

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().overlay(Color.ariLine) }
                    if Self.folds(card) {
                        DeskCardRow(card: card) { open(card) }
                    } else {
                        DeskCardView(
                            card: card, context: context(card), presentation: .inline
                        ) { try await answer(card, $0) }
                    }
                }
            }
            .deskCard()
        }
    }

    /// Whether a card shows as a row that opens it, rather than in full: drafts and times, which
    /// want a proper look before you answer.
    static func folds(_ card: DeskCard) -> Bool {
        card.kind == .draft || card.kind == .times || !card.kind.isKnown
    }
}

#if DEBUG
    #Preview("Waiting on you") {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DeskSectionLabel("Waiting on you", trailing: "\(DeskSamples.waiting.count)")
                WaitingList(
                    cards: DeskSamples.waiting, context: { _ in nil }, open: { _ in },
                    answer: { _, _ in try await Task.sleep(for: .seconds(1)) })
            }
            .padding(18)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }

    #Preview("Each kind") {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(DeskSamples.allCards) { card in
                    DeskCardView(card: card, context: DeskSamples.context(card)) { _ in
                        try await Task.sleep(for: .seconds(1))
                        throw RequestError.network(.notConnectedToInternet)
                    }
                }
            }
            .padding(16)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
