import AriKit
import Charts
import SwiftUI

/// A training block, open: the goal and your trend toward it, this week with today's session on a
/// card of its own, Ari's line on the week, every week of the block, and what changed. Tick a
/// session when it's done; Ari answers in the week's line.
struct TrainingView: View {
    let detail: MotionDetail
    let training: Training

    @Environment(Motions.self) private var motions: Motions?
    @State private var problem: String?
    @State private var ticks = 0

    var body: some View {
        let current = TrainingReading.currentWeek(of: training)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(training.goal.title).font(.ariTitle).foregroundStyle(.ariText)
                    Text(TrainingReading.subtitle(training)).font(.subheadline).foregroundStyle(
                        .ariSecondary)
                }
                if TrainingReading.best(training) != nil {
                    TrendCard(training: training)
                }
                if let current {
                    thisWeek(current.week)
                }
                if training.weeks.count > 1 {
                    allWeeks(current: current?.week.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 60)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private func thisWeek(_ week: Training.Week) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("This week").font(.ariHeading).foregroundStyle(.ariText)
                if let focus = week.focus {
                    Text("· \(focus)").font(.subheadline).foregroundStyle(.ariSecondary)
                }
            }
            ForEach(week.sessions) { session in
                SessionRow(
                    session: session, done: TrainingReading.isDone(session, in: detail.state),
                    today: TrainingReading.isToday(session)
                ) { tick(session, $0) }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.ariSecondary)
                    .task(id: problem) {
                        try? await Task.sleep(for: .seconds(4))
                        if !Task.isCancelled { self.problem = nil }
                    }
            }
            // Ari's line on the week, which it rewrites when you tick a session.
            if let note = week.note {
                Text(note)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    .padding(.top, 6)
                    .id(note)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.smooth(duration: 0.5), value: week.note)
    }

    private func allWeeks(current: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The block").font(.ariHeading).foregroundStyle(.ariText).padding(.bottom, 6)
            ForEach(Array(training.weeks.enumerated()), id: \.element.id) { index, week in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(week.sessions) { session in
                            SessionRow(
                                session: session,
                                done: TrainingReading.isDone(session, in: detail.state),
                                today: false
                            ) { tick(session, $0) }
                        }
                        if week.sessions.isEmpty {
                            Text("\(LeadName.current) writes this week's sessions nearer the time.")
                                .font(.footnote)
                                .foregroundStyle(.ariTertiary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    weekLabel(week, number: index + 1, isCurrent: week.id == current)
                }
                .tint(.ariTertiary)
                .padding(.vertical, 6)
            }
        }
    }

    private func weekLabel(_ week: Training.Week, number: Int, isCurrent: Bool) -> some View {
        let sessions = week.sessions.filter { $0.kind != .rest }
        let done = sessions.filter { TrainingReading.isDone($0, in: detail.state) }.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Week \(number)")
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.ariText : .ariSecondary)
            if let focus = week.focus {
                Text("· \(focus)").font(.subheadline).foregroundStyle(.ariTertiary)
            }
            Spacer()
            if !sessions.isEmpty {
                Text("\(done) of \(sessions.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(.ariTertiary)
            }
        }
    }

    private func tick(_ session: Training.Session, _ done: Bool) {
        ticks += 1
        Task {
            guard let motions else { return }
            let ticked = await motions.tick(
                detail.motion.id, list: TrainingReading.sessionsList, item: session.id, done: done)
            if !ticked { problem = "Couldn't tick that. Try again in a moment." }
        }
    }
}

/// Your best, how far is left, and the trend of your results toward the target.
private struct TrendCard: View {
    let training: Training

    @State private var drawn = false

    var body: some View {
        let points = training.results.compactMap { result -> (Date, Double)? in
            guard let date = TrainingReading.date(of: result),
                let value = TrainingReading.value(result.result)
            else { return nil }
            return (date, value)
        }
        let target = TrainingReading.value(training.goal.target)
        VStack(alignment: .leading, spacing: 12) {
            if let best = TrainingReading.best(training) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(best.result)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.ariText)
                    Text(
                        ["best", TrainingReading.toGo(training)].compactMap(\.self).joined(
                            separator: " · ")
                    )
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                }
            }
            if points.count > 1 {
                Chart {
                    ForEach(points, id: \.0) { point in
                        LineMark(x: .value("Day", point.0), y: .value("Result", point.1))
                            .foregroundStyle(.ariText)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Day", point.0), y: .value("Result", point.1))
                            .foregroundStyle(.ariText)
                            .symbolSize(18)
                    }
                    if let target {
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(.ariBone.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(training.goal.target).font(.caption2).foregroundStyle(
                                    .ariBone.opacity(0.85))
                            }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: Self.domain(points.map(\.1) + [target].compactMap(\.self)))
                .frame(height: 110)
                // The trend draws itself in, left to right.
                .mask(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle().frame(width: geometry.size.width * (drawn ? 1 : 0))
                    }
                }
                .onAppear { withAnimation(.easeInOut(duration: 1.2).delay(0.2)) { drawn = true } }
                .accessibilityLabel(
                    "Results: "
                        + training.results.map(\.result).joined(separator: ", "))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ariSurface, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// The values with room above and below.
    private static func domain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let room = max((high - low) * 0.15, 1)
        return (low - room)...(high + room)
    }
}

/// One session: a tick, what it is, its detail and how it went. Today's sits on a card.
private struct SessionRow: View {
    let session: Training.Session
    let done: Bool
    let today: Bool
    let tick: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                tick(!done)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.ariBone : .ariTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.kind == .rest)
            .opacity(session.kind == .rest ? 0 : 1)
            .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(done ? Color.ariSecondary : .ariText)
                    if today { StatusChip(text: "Today", filled: true) }
                }
                if let detail = session.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.ariSecondary)
                }
                if let how = session.how {
                    Text(how).font(.subheadline).italic().foregroundStyle(.ariTertiary)
                }
            }
            Spacer(minLength: 4)
            Text(TrainingReading.weekday(of: session)).font(.footnote).foregroundStyle(
                .ariTertiary)
        }
        .padding(today ? 14 : 4)
        .background {
            if today {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ariSurface)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
        .accessibilityElement(children: .combine)
    }
}
