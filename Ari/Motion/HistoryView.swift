import AriKit
import SwiftUI

/// What ended, by month, each with how it ended and Kumo's line. A copy, a test and small admin
/// kept elsewhere are never here. Each opens its short story.
struct HistoryView: View {
    @Environment(Motions.self) private var motions: Motions?
    @Environment(\.motionOpener) private var opener

    var body: some View {
        let done = motions?.done ?? []
        let months = InMotionReading.history(done)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                tally(done, months: months)
                ForEach(months) { month in
                    VStack(alignment: .leading, spacing: 10) {
                        MotionLabel(month.start.formatted(.dateTime.month(.wide).year()))
                        VStack(spacing: 0) {
                            ForEach(month.items) { motion in
                                row(motion)
                                if motion.id != month.items.last?.id {
                                    Hairline().padding(.leading, 62)
                                }
                            }
                        }
                        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.ariBackground)
        .navigationTitle("History")
    }

    /// Everything that ended, as marks, with the counts under them.
    private func tally(_ done: [Motion], months: [InMotionReading.Month]) -> some View {
        let all = months.flatMap(\.items)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(all.prefix(16)) { OutcomeMark(outcome: $0.outcome, side: 14) }
            }
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(InMotionReading.tally(done), id: \.outcome) { entry in
                    HStack(spacing: 4) {
                        Text("\(entry.count)").fontWeight(.semibold).foregroundStyle(.ariText)
                        Text(entry.outcome.name.lowercased()).foregroundStyle(.ariTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.footnote.monospacedDigit())
            if let oldest = months.last {
                Text("\(all.count) ended since \(oldest.start.formatted(.dateTime.month(.wide)))")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
        }
    }

    private func row(_ motion: Motion) -> some View {
        let source = "history \(motion.id)"
        return Button {
            opener.open?(motion.id, source)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                HalftoneArt(
                    art: motion.section, side: 36, across: 20, faded: motion.outcome != .achieved)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(motion.title).font(.headline).foregroundStyle(.ariText).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(
                            InMotionReading.endedAt(motion),
                            format: .dateTime.day().month(.abbreviated)
                        )
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        OutcomeLabel(outcome: motion.outcome, plain: true)
                        Text(motion.summary)
                            .font(.footnote)
                            .foregroundStyle(.ariSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motionSource(source, in: opener.namespace)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens its story")
    }
}

/// An ended thing's short story: how it ended, the plan against what happened where there are
/// results to draw, what happened, what you learnt, what followed, and Kumo's notes folded.
struct StoryView: View {
    let detail: MotionDetail

    @Environment(Motions.self) private var motions: Motions?

    private var motion: Motion { detail.motion }
    private var story: MotionStory? { detail.extras.story }

    var body: some View {
        MotionPage {
            MotionPageHead(
                art: motion.section, kicker: kicker, title: motion.title,
                faded: motion.outcome != .achieved)
            OutcomeLabel(outcome: motion.outcome, large: true).padding(.top, 12)
            KumoLine(motion.summary).padding(.top, 14)

            if case .body(let block) = detail.content, let results = BodyReading.results(block) {
                MotionLabel("The plan and what happened").padding(.top, 28)
                ResultsChart(points: results.points, goal: results.goal).padding(.top, 10)
            } else if case .career(let career) = detail.content {
                Pipeline(
                    stage: CareerReading.position(of: career), node: 10, line: 2.5,
                    labels: ["lead", "talking", "interviewing", "offer"],
                    dates: CareerReading.dates(of: career), faded: true
                )
                .padding(.top, 24)
            }

            if let story {
                MotionLabel("What happened").padding(.top, 28)
                Text(story.happened)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if !story.learnt.isEmpty {
                    MotionLabel("What you learnt").padding(.top, 28)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(story.learnt.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(.ariBone).frame(width: 5, height: 5)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                                Text(line)
                                    .font(.ariBody)
                                    .foregroundStyle(.ariText)
                                    .lineSpacing(Rhythm.ariLineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                if story.followed != nil || story.followedBy != nil {
                    MotionLabel("What followed").padding(.top, 28)
                    followed(story).padding(.top, 10)
                }
            } else if motion.outcome == .merged, let into = motion.mergedInto {
                MotionLabel("Went into").padding(.top, 28)
                link(to: into, line: nil).padding(.top, 10)
            }

            KumoNotes(notes: detail.extras.notes).padding(.top, 28)

            if hasContent {
                NavigationLink {
                    MotionContentView(detail: detail, asItWas: true)
                        .background(.ariBackground)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text("What it held").font(.subheadline).foregroundStyle(.ariSecondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(
                            .ariTertiary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, detail.extras.notes.isEmpty ? 28 : 0)
            }
        }
    }

    private var hasContent: Bool {
        switch detail.content {
        case .unknown, .unreadable: false
        default: true
        }
    }

    /// "Body · 15 Sep – 9 Nov".
    private var kicker: String {
        let start = motion.startedAt.date.formatted(.dateTime.day().month(.abbreviated))
        let end = InMotionReading.endedAt(motion).formatted(.dateTime.day().month(.abbreviated))
        return "\(motion.section.kicker) · \(start) – \(end)"
    }

    @ViewBuilder
    private func followed(_ story: MotionStory) -> some View {
        if let next = story.followedBy {
            link(to: next, line: story.followed)
        } else if let line = story.followed {
            Text(line).font(.ariBody).foregroundStyle(.ariText)
        }
    }

    /// Another thing in motion, to open from here.
    private func link(to id: MotionID, line: String?) -> some View {
        let other = motions?[id]
        return NavigationLink {
            LinkedMotionView(id: id)
        } label: {
            MotionCard(padding: 14) {
                HStack(spacing: 12) {
                    HalftoneArt(art: other?.section ?? .other, side: 40, across: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(other?.title ?? line ?? id.rawValue).font(.headline).foregroundStyle(
                            .ariText)
                        if let summary = other?.summary ?? (other == nil ? nil : line) {
                            Text(summary).font(.footnote).foregroundStyle(.ariSecondary).lineLimit(
                                2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(other == nil)
    }
}

/// The timed efforts that happened, solid, against the goal, dashed across.
private struct ResultsChart: View {
    let points: [BodyReading.Point]
    let goal: Double

    var body: some View {
        let best = points.map(\.value).min() ?? goal
        MotionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(Pace.text(Int(points.first?.value ?? 0)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.ariTertiary).fixedSize()
                    MiniLine(values: points.map(\.value), invert: true, target: goal).frame(
                        height: 96)
                    Text(Pace.text(Int(points.last?.value ?? 0)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.ariBone).fixedSize()
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Capsule().fill(.ariBone).frame(width: 14, height: 2)
                        Text("results").font(.caption2).foregroundStyle(.ariTertiary)
                    }
                    HStack(spacing: 5) {
                        Line().stroke(
                            Color.ariBone.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .frame(width: 14, height: 2)
                        Text("\(Pace.text(Int(goal))) goal").font(.caption2).foregroundStyle(
                            .ariTertiary)
                    }
                    Spacer()
                    Text(
                        best <= goal
                            ? "best \(Pace.text(Int(best)))"
                            : "best \(Pace.text(Int(best))) · \(Pace.text(Int(best - goal))) short"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.ariText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Results from \(Pace.text(Int(points.first?.value ?? 0))) to \(Pace.text(Int(points.last?.value ?? 0))), "
                + "against a goal of \(Pace.text(Int(goal)))")
    }
}
