import AriKit
import SwiftUI

/// A training block as a coach shows it: this week and next as they'll really go, planned against
/// done, the block's trends where there's real data to draw, and why the plan changed. A chart with
/// nothing to show isn't drawn at all.
struct BodyView: View {
    let detail: MotionDetail
    let block: BodyBlock

    @State private var openedSession: String?

    private var state: MotionState { detail.state }

    var body: some View {
        let current = BodyReading.currentWeek(of: block)
        MotionPage {
            MotionPageHead(
                art: .body,
                kicker: ["Body", current.map { "week \($0.number) of \(block.weeks.count)" }]
                    .compactMap(\.self).joined(separator: " · "),
                title: detail.motion.title,
                subtitle: subtitle)
            KumoLine(detail.motion.summary).padding(.top, 16)

            if let current {
                MotionLabel(
                    "This week and next", trailing: BodyReading.timeLine(current.week, state: state)
                )
                .padding(.top, 28)
                TwoWeeks(block: block, state: state, number: current.number).padding(.top, 10)

                let sessions = current.week.sessions.filter { $0.kind != .rest }
                if !sessions.isEmpty {
                    MotionLabel("Planned vs done").padding(.top, 30)
                    PlannedVsDone(sessions: sessions, state: state) { openedSession = $0 }
                        .padding(.top, 10)
                }
            }

            BlockTrends(block: block, state: state)

            if !detail.extras.reasons.isEmpty {
                MotionLabel("Why it changed").padding(.top, 30)
                ReasonsList(reasons: detail.extras.reasons).padding(.top, 12)
            }

            KumoNotes(notes: detail.extras.notes).padding(.top, 30)
        }
        #if DEBUG
            .task { if let id = DebugScript.motionPlace { openedSession = id } }
        #endif
        .navigationDestination(item: $openedSession) { id in
            if let session = block.weeks.flatMap(\.sessions).first(where: { $0.id == id }) {
                SessionView(detail: detail, block: block, session: session)
            }
        }
    }

    /// "2 lifts and 2 easy runs a week · up to 7 hours".
    private var subtitle: String {
        var parts: [String] = []
        if let plan = block.plan { parts.append(plan) }
        if let hours = block.hoursAWeek {
            parts.append("up to \(BodyReading.decimal(hours)) hours")
        }
        if parts.isEmpty, let goal = block.goal { parts.append(goal.title) }
        return parts.joined(separator: " · ")
    }
}

/// This week and next, each as a strip, with the legend for how they're drawn.
private struct TwoWeeks: View {
    let block: BodyBlock
    let state: MotionState
    /// This week's number, from 1.
    let number: Int

    var body: some View {
        let this = BodyReading.strip(block.weeks[number - 1], in: block, state: state)
        MotionCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(this) { day in
                        VStack(spacing: 1) {
                            Text(day.letter).font(.caption2.weight(.semibold))
                            Text("\(day.number)").font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(day.isToday ? Color.ariBone : .ariTertiary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                WeekStrip(days: this, barHeight: 50, letters: false)
                if number < block.weeks.count {
                    let next = block.weeks[number]
                    HStack {
                        Text("Next week").font(.caption).foregroundStyle(.ariTertiary)
                        Spacer()
                        if let time = BodyReading.plannedTime(next, state: state) {
                            Text(time).font(.caption.monospacedDigit()).foregroundStyle(
                                .ariTertiary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    WeekStrip(
                        days: BodyReading.strip(next, in: block, state: state), barHeight: 50,
                        letters: false)
                }
                Hairline().padding(.top, 2)
                HStack(spacing: 14) {
                    legend("done") { RoundedRectangle(cornerRadius: 2).fill(.ariBone) }
                    legend("planned") {
                        DotFill(step: 2.6, size: 0.32).clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    legend("moved") {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(
                            Color.ariTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityHidden(true)
            }
        }
    }

    private func legend<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark().frame(width: 9, height: 12)
            Text(text).font(.caption2).foregroundStyle(.ariTertiary)
        }
    }
}

/// This week's sessions, each with what was planned and what was done; each opens on its own.
private struct PlannedVsDone: View {
    let sessions: [BodyBlock.Session]
    let state: MotionState
    let open: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sessions) { session in
                Button {
                    open(session.id)
                } label: {
                    row(session).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the session")
                if session.id != sessions.last?.id { Hairline().padding(.leading, 52) }
            }
        }
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func row(_ session: BodyBlock.Session) -> some View {
        let did = BodyReading.did(session, state: state)
        let isToday = session.date.rawValue == BodyReading.day(of: .now, in: .current)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: SessionSymbol.name(session.kind))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(did != nil ? Color.ariBackground : .ariBone)
                .frame(width: 26, height: 26)
                .background {
                    if did != nil {
                        Circle().fill(.ariBone)
                    } else if session.letGo {
                        Circle().strokeBorder(
                            Color.ariTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    } else {
                        DotFill(step: 2.8, size: 0.3).clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.ariBone.opacity(0.6)))
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.title).font(.headline).foregroundStyle(.ariText)
                    Text(dayLabel(session)).font(.footnote).foregroundStyle(.ariTertiary)
                    Spacer(minLength: 4)
                    if isToday, did == nil {
                        StatusChip(text: "Today", filled: true)
                    } else if session.result?.source == .watch {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                            .accessibilityLabel("From your Watch")
                    }
                }
                if let plan = planLine(session) { line("PLAN", plan, color: .ariTertiary) }
                if let did { line("DID", did, color: .ariText) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func planLine(_ session: BodyBlock.Session) -> String? {
        var parts = [BodyReading.plan(of: session)].compactMap(\.self)
        if let moved = session.movedFrom, let date = BodyReading.noon(moved.rawValue) {
            parts.append("moved from \(date.formatted(.dateTime.weekday(.wide)))")
        }
        if session.letGo { parts.append("let go") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dayLabel(_ session: BodyBlock.Session) -> String {
        BodyReading.noon(session.date.rawValue)?.formatted(.dateTime.weekday(.abbreviated).day())
            ?? session.date.rawValue
    }

    private func line(_ tag: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tag)
                .font(.system(size: 9, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(.ariTertiary)
                .fixedSize()
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.footnote)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The block's trends, each only where there's real data: hours a week from the sessions, run
/// pace from the Watch, and the heaviest load where Kumo recorded sets.
private struct BlockTrends: View {
    let block: BodyBlock
    let state: MotionState

    var body: some View {
        let hours = BodyReading.hours(block, state: state)
        let pace = BodyReading.pace(block, state: state)
        let load = BodyReading.load(block, state: state)
        if hours != nil || pace != nil || load != nil {
            MotionLabel("The block", trailing: "\(block.weeks.count) weeks").padding(.top, 30)
            MotionCard {
                VStack(alignment: .leading, spacing: 18) {
                    if let hours {
                        VStack(alignment: .leading, spacing: 8) {
                            title(
                                "Hours a week",
                                value:
                                    "\(BodyReading.decimal((hours.map(\.done).reduce(0, +) * 10).rounded() / 10)) h so far"
                            )
                            HoursChart(weeks: hours, budget: block.hoursAWeek)
                        }
                    }
                    if let pace {
                        if hours != nil { Hairline() }
                        trend(
                            "Run pace", value: "\(Pace.text(Int(pace.last?.value ?? 0))) /km",
                            points: pace, invert: true,
                            first: Pace.text(Int(pace.first?.value ?? 0)),
                            last: Pace.text(Int(pace.last?.value ?? 0)))
                    }
                    if let load {
                        if hours != nil || pace != nil { Hairline() }
                        trend(
                            load.exercise,
                            value: "\(BodyReading.decimal(load.points.last?.value ?? 0)) kg",
                            points: load.points, invert: false,
                            first: BodyReading.decimal(load.points.first?.value ?? 0),
                            last: BodyReading.decimal(load.points.last?.value ?? 0))
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func title(_ text: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.ariText)
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.ariSecondary)
        }
    }

    private func trend(
        _ name: String, value: String, points: [BodyReading.Point], invert: Bool, first: String,
        last: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title(name, value: value)
            HStack(spacing: 10) {
                Text(first).font(.caption2.monospacedDigit()).foregroundStyle(.ariTertiary)
                    .fixedSize()
                MiniLine(values: points.map(\.value), invert: invert).frame(height: 44)
                Text(last).font(.caption2.monospacedDigit()).foregroundStyle(.ariBone).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): from \(first) to \(last)")
    }
}

/// Hours a week through the block: done solid, still planned in dots, under the week's budget.
private struct HoursChart: View {
    let weeks: [BodyReading.WeekHours]
    let budget: Double?
    let height: CGFloat = 92

    private var top: Double {
        max(budget ?? 0, weeks.map { $0.done + $0.planned }.max() ?? 0, 1) * 1.15
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(weeks) { week in
                VStack(spacing: 5) {
                    VStack(spacing: 0) {
                        if week.planned > 0 {
                            DotFill(step: 3, size: 0.3)
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 3, topTrailingRadius: 3)
                                )
                                .overlay(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 3, topTrailingRadius: 3
                                    )
                                    .strokeBorder(Color.ariBone.opacity(0.45), lineWidth: 1)
                                )
                                .frame(height: scaled(week.planned))
                        }
                        if week.done > 0 {
                            UnevenRoundedRectangle(
                                topLeadingRadius: week.planned > 0 ? 0 : 3,
                                bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                                topTrailingRadius: week.planned > 0 ? 0 : 3
                            )
                            .fill(.ariBone)
                            .frame(height: scaled(week.done))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .bottom)
                    Text("\(week.number)")
                        .font(.caption2.monospacedDigit().weight(week.isCurrent ? .bold : .regular))
                        .foregroundStyle(week.isCurrent ? Color.ariBone : .ariTertiary)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let budget {
                ZStack(alignment: .leading) {
                    Line()
                        .stroke(
                            Color.ariBone.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .frame(height: 1)
                    Text("\(BodyReading.decimal(budget)) h budget")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.ariBone.opacity(0.8))
                        .padding(.trailing, 4)
                        .background(.ariSurface)
                        .offset(y: -8)
                }
                .offset(y: height - scaled(budget))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            weeks.map {
                "Week \($0.number): \(BodyReading.decimal(($0.done * 10).rounded() / 10)) hours done"
            }
            .joined(separator: ", "))
    }

    private func scaled(_ hours: Double) -> CGFloat { max(2, height * hours / top) }
}

// MARK: - A session

/// One session, open: what was prescribed against what happened, how it was spread, what it
/// changes, and Kumo's notes folded away. Only what's known shows.
struct SessionView: View {
    let detail: MotionDetail
    let block: BodyBlock
    let session: BodyBlock.Session

    var body: some View {
        let result = session.result
        let isDone = BodyReading.isDone(session, in: detail.state)
        MotionPage {
            MotionPageHead(
                art: .body, kicker: kicker, title: session.title,
                symbol: SessionSymbol.name(session.kind))
            if let line = session.line { KumoLine(line).padding(.top, 16) }
            if let result, result.source == .watch {
                HStack(spacing: 6) {
                    Image(systemName: "applewatch")
                    Text(["From your Watch", result.at].compactMap(\.self).joined(separator: ", "))
                }
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }

            let rows = BodyReading.comparison(session)
            if !rows.isEmpty {
                MotionLabel("Planned vs done").padding(.top, 28)
                PlanTable(rows: rows).padding(.top, 10)
            } else if let plan = BodyReading.plan(of: session) {
                MotionLabel("Planned").padding(.top, 28)
                Text(plan).font(.subheadline).foregroundStyle(.ariText).padding(.top, 8)
                if isDone, let did = BodyReading.did(session, state: detail.state) {
                    MotionLabel("Done").padding(.top, 20)
                    Text(did).font(.subheadline).foregroundStyle(.ariText).padding(.top, 8)
                }
            }

            if let sets = result?.sets, !sets.isEmpty {
                MotionLabel("Sets").padding(.top, 28)
                MotionCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sets.enumerated()), id: \.offset) { _, done in
                            HStack(alignment: .firstTextBaseline) {
                                Text(BodyReading.setsLine(done)).font(
                                    .subheadline.monospacedDigit()
                                )
                                .foregroundStyle(.ariText)
                                Spacer(minLength: 8)
                                if let note = done.note {
                                    Text(note).font(.footnote).foregroundStyle(.ariTertiary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }

            if let zones = result?.zones, !zones.isEmpty {
                MotionLabel(
                    "Heart rate",
                    trailing: [
                        result?.heartAvg.map { "\($0) avg" }, result?.heartMax.map { "\($0) max" },
                    ]
                    .compactMap(\.self).joined(separator: " · ")
                )
                .padding(.top, 28)
                ZoneBar(zones: zones).padding(.top, 10)
            }

            if let splits = result?.splits, splits.count >= 2 {
                MotionLabel("Splits", trailing: "per km").padding(.top, 28)
                Splits(splits: splits).padding(.top, 10)
            }

            if let next = session.changesNext {
                MotionLabel("What it changes").padding(.top, 28)
                Text(next).font(.subheadline).foregroundStyle(.ariText).padding(.top, 10)
            }

            KumoNotes(notes: session.notes).padding(.top, 30)
        }
        .background(.ariBackground)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Tue 17 Nov · Hybrid restart, week 1".
    private var kicker: String {
        let day =
            BodyReading.noon(session.date.rawValue)?.formatted(
                .dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? session.date.rawValue
        let week = block.weeks.firstIndex { $0.sessions.contains { $0.id == session.id } }
        return [day, week.map { "\(detailTitle), week \($0 + 1)" }].compactMap(\.self)
            .joined(separator: " · ")
    }

    private var detailTitle: String { detail.motion.title }
}

/// Planned against done, a row a measure, with how they compare.
private struct PlanTable: View {
    let rows: [BodyReading.Comparison]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("").frame(width: 66, alignment: .leading)
                Text("PLANNED").frame(maxWidth: .infinity, alignment: .leading)
                Text("DONE").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(.ariTertiary)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).foregroundStyle(.ariTertiary).frame(
                        width: 66, alignment: .leading)
                    Text(row.planned ?? "–").foregroundStyle(.ariSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.done ?? "–").foregroundStyle(.ariText).fontWeight(.medium)
                        if let verdict = row.verdict {
                            HStack(spacing: 3) {
                                Image(
                                    systemName: verdict == .onPlan ? "checkmark" : "arrow.up.right"
                                )
                                .font(.system(size: 8, weight: .bold))
                                Text(verdict.words)
                            }
                            .font(.caption2)
                            .foregroundStyle(
                                verdict == .onPlan ? Color.ariBone.opacity(0.8) : .ariSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline.monospacedDigit())
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                if row.id != rows.last?.id { Hairline() }
            }
        }
        .padding(14)
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Time in each heart zone, each zone printed denser than the one below it.
private struct ZoneBar: View {
    let zones: [Int: Double]

    var body: some View {
        let ordered = zones.keys.sorted()
        let total = max(zones.values.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(ordered, id: \.self) { zone in
                        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                        Group {
                            if zone >= 4 {
                                shape.fill(.ariBone)
                            } else {
                                DotFill(
                                    step: 4.2 - Double(zone - 1) * 0.9,
                                    size: 0.24 + Double(zone - 1) * 0.07
                                )
                                .clipShape(shape)
                            }
                        }
                        .frame(
                            width: max(
                                6,
                                (geometry.size.width - CGFloat(3 * (ordered.count - 1)))
                                    * (zones[zone] ?? 0) / total))
                    }
                }
            }
            .frame(height: 22)
            HStack(spacing: 14) {
                ForEach(ordered, id: \.self) { zone in
                    HStack(spacing: 4) {
                        Text("Z\(zone)").fontWeight(.semibold).foregroundStyle(.ariSecondary)
                        Text("\(Int((zones[zone] ?? 0).rounded()))m").foregroundStyle(.ariTertiary)
                    }
                }
            }
            .font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ordered.map { "Zone \($0), \(Int((zones[$0] ?? 0).rounded())) minutes" }.joined(
                separator: ", "))
    }
}

/// Each km's pace, taller for faster.
private struct Splits: View {
    let splits: [Int]

    var body: some View {
        let slowest = Double(splits.max() ?? 0)
        let fastest = Double(splits.min() ?? 0)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.ariBone.opacity(0.35 + 0.6 * share(split, slowest, fastest)))
                        .frame(height: 18 + 40 * share(split, slowest, fastest))
                        .padding(.horizontal, splits.count > 8 ? 2 : 10)
                    Text(Pace.text(split)).font(.caption2.monospacedDigit()).foregroundStyle(
                        .ariSecondary)
                    Text("km \(index + 1)").font(.system(size: 9)).foregroundStyle(.ariTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            splits.enumerated().map { "km \($0.offset + 1), \(Pace.text($0.element))" }.joined(
                separator: ", "))
    }

    private func share(_ split: Int, _ slowest: Double, _ fastest: Double) -> Double {
        slowest > fastest ? (slowest - Double(split)) / (slowest - fastest) : 0.5
    }
}
