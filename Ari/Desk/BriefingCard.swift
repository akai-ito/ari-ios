import AriKit
import SwiftUI

/// Kumo's morning card, or "Since this morning" later on: Kumo's lines in its own hand, each that
/// leads somewhere (a space, a thing in motion, a card) tappable, then what else it handled. Once
/// read it folds to one line, "Morning · 2 things ›", which unfolds it again.
struct BriefingCard: View {
    let briefing: Briefing
    /// Folded to one line; tapping it unfolds it. The Desk folds it once you've read it.
    @Binding var folded: Bool
    /// Opens what a line is about: its card, else its thing in motion, else its space.
    let open: (BriefingLine) -> Void
    /// Shows the small things Kumo handled, as the Done of their spaces.
    let openHandled: () -> Void

    var body: some View {
        Group {
            if folded {
                foldedLine.transition(.opacity)
            } else {
                card.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: folded)
    }

    private var title: String {
        briefing.kind == .since ? "Since this morning" : "Morning"
    }

    private var things: String {
        briefing.lines.count == 1 ? "1 thing" : "\(briefing.lines.count) things"
    }

    private var foldedLine: some View {
        Button {
            folded = false
        } label: {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                Text("·").foregroundStyle(.ariTertiary)
                Text(things).font(.subheadline).foregroundStyle(.ariSecondary)
                Text("›").foregroundStyle(.ariTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .deskCard(padding: 14, cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(things)")
        .accessibilityHint("Shows the whole card")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.ariBone)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(briefing.at.date, format: DeskTime.time)
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(briefing.lines.enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
            if briefing.handled > 0 {
                Button(action: openHandled) {
                    Text("Also handled \(handled) \(Text("›").foregroundStyle(.ariTertiary))")
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Also handled \(handled)")
                .accessibilityHint("Shows what Kumo did")
            }
        }
        .deskCard()
    }

    private var handled: String {
        briefing.handled == 1 ? "1 small thing" : "\(briefing.handled) small things"
    }

    @ViewBuilder
    private func lineView(_ line: BriefingLine) -> some View {
        let words = Text(line.text)
        if Self.leadsSomewhere(line) {
            Button {
                open(line)
            } label: {
                Text("\(words) \(Text("›").foregroundStyle(.ariTertiary))")
                    .kumoLine()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.text)
            .accessibilityHint("Opens it")
        } else {
            words.kumoLine()
        }
    }

    static func leadsSomewhere(_ line: BriefingLine) -> Bool {
        line.card != nil
    }
}

extension Text {
    /// Kumo's own words: New York, full colour, with room between the lines.
    fileprivate func kumoLine() -> some View {
        self
            .font(.ariBody)
            .foregroundStyle(.ariText)
            .lineSpacing(Rhythm.ariLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview("Morning") {
        @Previewable @State var folded = false
        ScrollView {
            VStack(spacing: 16) {
                BriefingCard(
                    briefing: DeskSamples.morning, folded: $folded, open: { _ in },
                    openHandled: {})
                BriefingCard(
                    briefing: DeskSamples.since, folded: .constant(false), open: { _ in },
                    openHandled: {})
                BriefingCard(
                    briefing: DeskSamples.morning, folded: .constant(true), open: { _ in },
                    openHandled: {})
            }
            .padding(18)
        }
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
