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

    @Environment(\.offline) private var offline

    var body: some View {
        // Offline, its answers wait for the server: dimmed, never shown as sent.
        kind.disabled(offline.isOffline)
    }

    @ViewBuilder
    private var kind: some View {
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
        case .commit:
            CommitCardView(
                card: card, context: context, presentation: presentation, answer: answer)
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
    /// Whether it has anything to answer, which waits while offline.
    var answers = true
    @ViewBuilder let content: Content

    @Environment(\.offline) private var offline

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
                waiting
            }
            .deskCard()
        case .inline:
            HStack(alignment: .top, spacing: 12) {
                CardSymbol(kind: kind)
                VStack(alignment: .leading, spacing: 10) {
                    content
                    waiting
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Offline, under its dimmed buttons: why they wait.
    @ViewBuilder
    private var waiting: some View {
        if answers, offline.isOffline {
            Text("Back online to act on this")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
                .transition(.opacity)
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
        CardShell(kind: card.kind, presentation: presentation, answers: false) {
            Text(card.title)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
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
