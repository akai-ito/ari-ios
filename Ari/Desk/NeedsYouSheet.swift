import AriKit
import SwiftUI

/// What the "2 for you" bubble opens: just what waits on you, as rows, each opening its card in
/// full, as the Desk has it now. Once nothing waits, it closes itself.
struct NeedsYouSheet: View {
    let session: Session
    let mood: FaceMood

    @State private var path: [CardID] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 6) {
                        KumoFace(mood: mood, size: 50).frame(width: 60)
                        Text("For you")
                            .font(.ariHeading)
                            .foregroundStyle(.ariText)
                            .accessibilityAddTraits(.isHeader)
                    }
                    OfflineLine()
                    if waiting.isEmpty {
                        Text("Nothing waits on you.")
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, card in
                                if index > 0 {
                                    Divider().overlay(Color.ariBone.opacity(0.15)).padding(
                                        .leading, 30)
                                }
                                NeedsYouRow(card: card, context: context(for: card)) {
                                    path.append(card.id)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.ariBone.opacity(0.08)))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CardID.self) { id in
                if let card = waiting.first(where: { $0.id == id }) { cardView(card) }
            }
        }
        // Answered the last one, here or anywhere: nothing's left to show.
        .onChange(of: waiting.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    private var waiting: [DeskCard] { session.desk?.waiting ?? [] }

    /// A card that needs you, in full, as the Desk has it now.
    private func cardView(_ card: DeskCard) -> some View {
        ScrollView {
            DeskCardView(card: card, context: context(for: card)) { answer in
                try await session.answer(card.id, answer)
                path.removeAll { $0 == card.id }
            }
            .padding(16)
        }
        .background(.ariBackground)
        .navigationTitle(CardLook.name(card.kind))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// The card's corner: the thing in motion it's about, such as "Job search".
    private func context(for card: DeskCard) -> String? {
        guard let motion = card.motion else { return nil }
        return session.motions?.all.first { $0.id == motion }?.title
    }
}

/// A card that needs you, as one row: a bone dot, its title, where it belongs, and a chevron.
private struct NeedsYouRow: View {
    let card: DeskCard
    let context: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Circle().fill(.ariBone).frame(width: 6, height: 6)
                Text(card.title)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let context {
                    Text(context)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariBone.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!card.kind.isKnown)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }
}
