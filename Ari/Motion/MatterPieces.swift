import AriKit
import SwiftUI

// Pieces the new matter widgets share: a Pursuit, an Occasion and a Case.

/// What kind of matter it is, over its title ("Pursuit"), with the kind's symbol in a ring of bone
/// dots.
struct MatterEyebrow: View {
    /// Such as "Pursuit".
    let kind: String
    let motion: Motion

    @ScaledMetric(relativeTo: .caption) private var ring: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        Color.ariBone.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 4.2]))
                Image(systemName: MotionSymbol.name(for: motion.kind))
                    .font(.system(size: ring * 0.4, weight: .semibold))
                    .foregroundStyle(.ariBone)
            }
            .frame(width: ring, height: ring)
            .accessibilityHidden(true)
            Text(kind)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.ariTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind)
    }
}

/// A matter's section, under a quiet small-caps label: "What you're after".
struct MatterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.ariTertiary)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A matter's card: the surface, rounded, with a faint edge.
struct MatterCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.ariLine.opacity(0.7)))
    }
}

extension View {
    func matterCard() -> some View { modifier(MatterCard()) }
}

/// A small fact with its symbol: when, where, who.
struct MatterFact: View {
    let symbol: String
    let text: String

    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.ariTertiary)
                .frame(width: column)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.ariText)
                .multilineTextAlignment(.leading)
        }
        .font(.subheadline)
    }
}

/// Kumo's word that it keeps the matter, at the foot of a widget.
struct MatterFootnote: View {
    var body: some View {
        Text("Kumo keeps this. To change it, just tell Kumo.")
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
    }
}

/// The page a matter's widget sits on, under the close and What changed buttons.
struct MatterPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 60)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

#if DEBUG
    /// A matter's widget as MotionView shows it, for previews.
    struct MatterPreview<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            ZStack {
                Color.ariBackground.ignoresSafeArea()
                content
            }
            .preferredColorScheme(.dark)
        }
    }

    extension Timestamp {
        /// A moment this far from today at a time on the clock, for previews that stay current.
        static func day(_ days: Int, at hour: Int, _ minute: Int = 0) -> Timestamp {
            Timestamp(LocalTime.day(days, at: hour, minute).date.ISO8601Format())!
        }
    }

    extension LocalTime {
        /// A day this far from today at a time on the clock, for previews that stay current.
        static func day(_ days: Int, at hour: Int, _ minute: Int = 0) -> LocalTime {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: days, to: .now) ?? .now
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return LocalTime(
                String(
                    format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 0, parts.month ?? 0,
                    parts.day ?? 0, hour, minute))!
        }
    }
#endif
