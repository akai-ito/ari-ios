import AriKit
import SwiftUI

// The pieces In motion's pages share: a page's head and Kumo's line, the quiet labels over its
// parts, Kumo's notes folded at the bottom, and the marks for how far along something is and how it
// ended. Solid is done or booked, dotted is planned or still to book, dashed is moved or let go.

/// A page's scroll: the column, with room at the top for Close and More.
struct MotionPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 60)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A page's head: the kind and when in small caps, the title in the serif, and the accent's
/// hairline under it. Type only; the page's pipelines, weeks and charts are its pictures.
struct MotionPageHead: View {
    let kicker: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.ariTertiary)
            Text(title).font(.ariTitle).foregroundStyle(.ariText)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.ariSecondary)
            }
            AccentRule().padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The accent's hairline under a serif title: a section of In motion, or a page's head.
struct AccentRule: View {
    /// For an empty section: fainter still.
    var quiet = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.ariBone.opacity(quiet ? 0.12 : 0.28))
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// Kumo's line for you, in its serif hand.
struct KumoLine: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .serif))
            .foregroundStyle(.ariText)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The quiet heading over a part of a page: "PLANNED VS DONE", with something on the right.
struct MotionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.ariTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }
}

/// A rounded card on the surface.
struct MotionCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(.ariLine).frame(height: 1) }
}

/// A row of facts: a quiet label and its value.
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.ariTertiary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.ariText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Kumo's working notes for a thing, folded at the bottom of its page: where each fact came from,
/// what's a guess, how it got here, and the ids it works with. Yours to read, never inline.
struct KumoNotes: View {
    let notes: [MotionNote]
    @State private var open = false

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { open.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariTertiary)
                            .frame(width: 14)
                        Text("\(LeadName.current)'s notes")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.ariSecondary)
                        Text("\(notes.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.ariTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Color.ariLine))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityValue(open ? "Open" : "Folded")
                if open {
                    Text(
                        "What \(LeadName.current) works from: where each part came from, what it's "
                            + "unsure of, and how it got here."
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .padding(.bottom, 14)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(notes) { note in
                            row(note)
                            if note.id != notes.last?.id {
                                Rectangle().fill(.ariLine.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(
                        .ariSurface.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous)
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    private func row(_ note: MotionNote) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(note.tag.name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.6)
                    .foregroundStyle(
                        note.tag == .guess || note.tag == .unsure ? Color.ariBone : .ariTertiary)
                if let at = note.at {
                    Text("· \(CareerReading.short(at))").font(.caption2).foregroundStyle(
                        .ariTertiary)
                }
            }
            Text(note.text)
                .font(note.tag == .ids ? .caption.monospaced() : .footnote)
                .foregroundStyle(note.tag == .ids ? Color.ariTertiary : .ariSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// Why the plan changed, newest first, on a rail like the chat's trail.
struct ReasonsList: View {
    let reasons: [MotionReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(reasons.enumerated()), id: \.element.id) { index, reason in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? Color.ariBone : .ariDusk)
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        if index < reasons.count - 1 {
                            Rectangle().fill(.ariLine).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if let because = reason.because {
                                Text("\(Text(reason.change).foregroundStyle(.ariText)): \(because)")
                            } else {
                                Text(reason.change).foregroundStyle(.ariText)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(CareerReading.short(reason.date)).font(.caption).foregroundStyle(
                            .ariTertiary)
                    }
                    .padding(.bottom, 16)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A role's way along lead, talking, interviewing, offer: solid where it's been, a ring where it
/// is, hollow ahead. With labels, each stage's name (and date) sits under its node.
struct Pipeline: View {
    let stage: Int
    var node: CGFloat = 8
    var line: CGFloat = 2
    var labels: [String]?
    var dates: [String?]?
    /// Ended: everything dimmed.
    var faded = false

    private var ahead: Color { Color.ariTertiary.opacity(0.45) }
    private var count: Int { labels?.count ?? 4 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(index <= stage ? Color.ariBone : ahead)
                        .frame(height: index <= stage ? line : max(1, line * 0.6))
                        .frame(maxWidth: .infinity)
                }
                dot(index)
                    .frame(width: node * 1.75, height: node * 1.75)
                    .overlay(alignment: alignment(index)) {
                        if let labels { label(index, labels[index]) }
                    }
            }
        }
        .padding(.bottom, labels == nil ? 0 : dates == nil ? 22 : 36)
        .opacity(faded ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private func alignment(_ index: Int) -> Alignment {
        index == 0 ? .topLeading : index == count - 1 ? .topTrailing : .top
    }

    private func label(_ index: Int, _ name: String) -> some View {
        VStack(
            alignment: index == 0 ? .leading : index == count - 1 ? .trailing : .center, spacing: 2
        ) {
            Text(name)
                .font(.caption.weight(index == stage ? .semibold : .regular))
                .foregroundStyle(
                    index == stage ? Color.ariBone : index < stage ? .ariSecondary : .ariTertiary)
            if let dates, index < dates.count, let date = dates[index] {
                Text(date).font(.caption2.monospacedDigit()).foregroundStyle(.ariTertiary)
            }
        }
        .fixedSize()
        .offset(y: node * 1.75 + 6)
    }

    @ViewBuilder
    private func dot(_ index: Int) -> some View {
        if index < stage {
            Circle().fill(.ariBone).frame(width: node, height: node)
        } else if index == stage {
            Circle()
                .strokeBorder(Color.ariBone, lineWidth: line)
                .overlay(Circle().fill(.ariBone).frame(width: node * 0.75, height: node * 0.75))
        } else {
            Circle().strokeBorder(ahead, lineWidth: max(1, line * 0.6))
                .frame(width: node, height: node)
        }
    }
}

/// Parts of a whole: solid when done, dotted while going, an outline still to start, dashed when
/// dropped.
struct Segments: View {
    let parts: [MotionPart.Status]
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, status in
                let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
                Group {
                    switch status {
                    case .done:
                        shape.fill(.ariBone)
                    case .doing:
                        DotFill(step: 3, size: 0.32).clipShape(shape)
                            .overlay(shape.strokeBorder(Color.ariBone.opacity(0.5), lineWidth: 1))
                    case .dropped:
                        shape.strokeBorder(
                            Color.ariTertiary.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    default:
                        shape.strokeBorder(Color.ariLine, lineWidth: 1)
                    }
                }
                .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// How something ended, as a mark: solid when achieved, half when not met, a dashed ring when let
/// go, two joining when merged, and a plain ring when it ended untold.
struct OutcomeMark: View {
    let outcome: MotionOutcome?
    var side: CGFloat = 10

    var body: some View {
        Group {
            switch outcome {
            case .achieved?:
                Circle().fill(.ariBone)
            case .notMet?:
                Circle().strokeBorder(Color.ariBone, lineWidth: max(1, side * 0.12))
                    .background(
                        Circle().fill(.ariBone).mask(
                            Rectangle().frame(width: side / 2).frame(
                                maxWidth: .infinity, alignment: .leading)))
            case .letGo?:
                Circle().strokeBorder(
                    Color.ariTertiary,
                    style: StrokeStyle(lineWidth: max(1, side * 0.12), dash: [1.5, 1.5]))
            case .merged?:
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: side * 0.9, weight: .bold))
                    .foregroundStyle(.ariSecondary)
            default:
                Circle().strokeBorder(Color.ariTertiary, lineWidth: max(1, side * 0.12))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// How something ended, as its mark and its name.
struct OutcomeLabel: View {
    let outcome: MotionOutcome?
    var large = false
    /// Inline in a line of text, without its capsule.
    var plain = false

    var body: some View {
        HStack(spacing: 5) {
            OutcomeMark(outcome: outcome, side: large ? 11 : 9)
            Text(outcome?.name ?? "Ended")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, plain ? 0 : large ? 10 : 8)
        .padding(.vertical, plain ? 0 : large ? 5 : 4)
        .overlay {
            if !plain { Capsule().strokeBorder(Color.ariLine) }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch outcome {
        case .achieved?: .ariBone
        case .notMet?: .ariText
        case .merged?: .ariSecondary
        default: .ariTertiary
        }
    }
}

/// What Kumo folded away as quieter, one tap from opening.
struct QuieterLink: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.footnote)
        .foregroundStyle(.ariTertiary)
        .padding(.leading, 16)
        .contentShape(Rectangle())
    }
}

/// A straight line across the middle of its frame.
nonisolated struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A small line of values over time: solid through what happened, with a dashed target where
/// there is one.
struct MiniLine: View {
    let values: [Double]
    /// Lower is better, so it's drawn rising.
    var invert = false
    var target: Double?

    var body: some View {
        Canvas { context, size in
            let known = values + [target].compactMap(\.self)
            guard let low = known.min(), let high = known.max(), high > low else { return }
            func point(_ index: Int, _ value: Double) -> CGPoint {
                var t = (value - low) / (high - low)
                if invert { t = 1 - t }
                return CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(max(1, values.count - 1)),
                    y: size.height - 5 - (size.height - 10) * t)
            }
            if let target {
                let y = point(0, target).y
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    rule, with: .color(.ariBone.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            var path = Path()
            for (index, value) in values.enumerated() {
                if index == 0 {
                    path.move(to: point(index, value))
                } else {
                    path.addLine(to: point(index, value))
                }
            }
            context.stroke(
                path, with: .color(.ariBone),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (index, value) in values.enumerated() {
                let p = point(index, value)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                    with: .color(.ariBone))
            }
        }
        .accessibilityHidden(true)
    }
}

extension MotionSection {
    /// The section, as a page's kicker says it: "Career", "Body", "Trip"…
    var kicker: String {
        switch self {
        case .trips: "Trip"
        case .projects: "Project"
        default: name
        }
    }
}

/// An area filled with an even grid of small dots: something planned, not yet done. Done things
/// are solid; plans are printed in dots.
struct DotFill: View {
    var step: CGFloat = 3.4
    var size: CGFloat = 0.3
    var color: Color = .ariBone

    var body: some View {
        Canvas { context, canvas in
            var dots = Path()
            var y = step / 2
            var row = 0
            while y < canvas.height + step {
                var x = step / 2 + (row.isMultiple(of: 2) ? 0 : step / 2)
                while x < canvas.width + step {
                    let r = step * size
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    x += step
                }
                y += step * 0.866
                row += 1
            }
            context.fill(dots, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}
