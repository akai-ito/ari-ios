import Foundation

/// How a training block reads as a coach would show it: the week you're in and the next as strips,
/// planned against done, and the trends across the block. Every chart is drawn only from real
/// results, from the Watch or from what you said: one with nothing to show is `nil`, never made up.
/// Days are your own, in the device's calendar; your ticks win over how Kumo wrote a session.
public enum BodyReading {
    /// The sessions' list name in the state, whichever week a session is in.
    public static let sessionsList = "sessions"

    /// How a session shows: solid when done, dotted when planned, dashed when moved or let go.
    public enum Mark: Sendable, Equatable {
        case done
        case planned
        /// Where a session was before it moved: a dashed ghost.
        case moved
        case letGo
    }

    /// One day of a week's strip, and what's on it.
    public struct Day: Sendable, Equatable, Identifiable {
        /// Such as `2026-11-17`.
        public let date: String
        /// "M", "T", "W"…
        public let letter: String
        /// The day of the month, such as 17.
        public let number: Int
        public let isToday: Bool
        public let sessions: [Cell]

        public var id: String { date }
    }

    /// A session on a day of the strip.
    public struct Cell: Sendable, Equatable, Identifiable {
        public let session: BodyBlock.Session
        public let mark: Mark
        /// How long, done or planned, for the bar's height; `nil` when nobody knows.
        public let minutes: Double?

        public var id: String { "\(session.id) \(mark)" }
    }

    /// Whether a session is done: your tick if you've made one, otherwise how Kumo wrote it.
    public static func isDone(_ session: BodyBlock.Session, in state: MotionState) -> Bool {
        state[sessionsList]?[session.id]?.done ?? session.done
    }

    /// The week you're in, numbered through the block from 1: before the block its first week, and
    /// after it its last.
    public static func currentWeek(
        of block: BodyBlock, now: Date = .now, calendar: Calendar = .current
    ) -> (number: Int, week: BodyBlock.Week)? {
        let today = day(of: now, in: calendar)
        let index =
            block.weeks.lastIndex { $0.start.rawValue <= today } ?? (block.weeks.isEmpty ? nil : 0)
        return index.map { ($0 + 1, block.weeks[$0]) }
    }

    /// "Week 1 of 8".
    public static func weekLine(
        of block: BodyBlock, now: Date = .now, calendar: Calendar = .current
    ) -> String? {
        currentWeek(of: block, now: now, calendar: calendar).map {
            "Week \($0.number) of \(block.weeks.count)"
        }
    }

    /// A week as seven days from its start, each with its sessions, and a ghost wherever a
    /// session moved from.
    public static func strip(
        _ week: BodyBlock.Week, in block: BodyBlock, state: MotionState, now: Date = .now,
        calendar: Calendar = .current
    ) -> [Day] {
        let today = day(of: now, in: calendar)
        let all = block.weeks.flatMap(\.sessions)
        return (0..<7).map { offset in
            let date = adding(offset, to: week.start.rawValue)
            let here = all.filter { $0.date.rawValue == date }.map { session in
                Cell(
                    session: session,
                    mark: session.letGo ? .letGo : isDone(session, in: state) ? .done : .planned,
                    minutes: minutes(of: session, in: state))
            }
            let ghosts = all.filter { $0.movedFrom?.rawValue == date }.map { session in
                Cell(session: session, mark: .moved, minutes: plannedMinutes(of: session))
            }
            return Day(
                date: date, letter: letter(of: date), number: Int(date.suffix(2)) ?? 0,
                isToday: date == today, sessions: here + ghosts)
        }
    }

    /// The sessions that count in a week: neither rest days nor ones let go.
    public static func counted(_ week: BodyBlock.Week) -> [BodyBlock.Session] {
        week.sessions.filter { $0.kind != .rest && !$0.letGo }
    }

    /// "3 of 4 done".
    public static func doneLine(_ week: BodyBlock.Week, state: MotionState) -> String {
        let sessions = counted(week)
        return "\(sessions.filter { isDone($0, in: state) }.count) of \(sessions.count) done"
    }

    /// Time done this week against all of it: "2h 30m of 3h 05m"; `nil` when no session has a
    /// length.
    public static func timeLine(_ week: BodyBlock.Week, state: MotionState) -> String? {
        let sessions = counted(week)
        let total = sessions.compactMap { minutes(of: $0, in: state) }
        guard !total.isEmpty else { return nil }
        let done = sessions.filter { isDone($0, in: state) }.compactMap {
            minutes(of: $0, in: state)
        }
        return "\(duration(done.reduce(0, +))) of \(duration(total.reduce(0, +)))"
    }

    /// A week's planned time, such as "3h 20m"; `nil` when nothing has a length.
    public static func plannedTime(_ week: BodyBlock.Week, state: MotionState) -> String? {
        let total = counted(week).compactMap { minutes(of: $0, in: state) }
        return total.isEmpty ? nil : duration(total.reduce(0, +))
    }

    /// Today's session still to do, if there is one.
    public static func today(
        in block: BodyBlock, state: MotionState, now: Date = .now, calendar: Calendar = .current
    ) -> BodyBlock.Session? {
        let today = day(of: now, in: calendar)
        return block.weeks.lazy.flatMap(\.sessions).first {
            $0.date.rawValue == today && !isDone($0, in: state) && !$0.letGo && $0.kind != .rest
        }
    }

    /// The next session still to do, from today on.
    public static func next(
        in block: BodyBlock, state: MotionState, now: Date = .now, calendar: Calendar = .current
    ) -> BodyBlock.Session? {
        let today = day(of: now, in: calendar)
        return block.weeks.lazy.flatMap(\.sessions).first {
            $0.date.rawValue >= today && !isDone($0, in: state) && !$0.letGo && $0.kind != .rest
        }
    }

    /// A session's prescription in a line: Kumo's, or 0.18's detail.
    public static func plan(of session: BodyBlock.Session) -> String? {
        session.plan ?? session.detail
    }

    /// What happened, in a line: "31 min · 5.2 km · 5:59/km · 146 bpm · felt easy", the sets for a
    /// lift, or how you said it went. `nil` until it's done.
    public static func did(_ session: BodyBlock.Session, state: MotionState) -> String? {
        guard isDone(session, in: state) else { return nil }
        guard let result = session.result else { return session.how ?? "Done" }
        var parts: [String] = []
        // A lift reads by its sets, anything else by its numbers.
        if session.kind.plain == .lift, !result.sets.isEmpty {
            parts.append(result.sets.map(setsLine).joined(separator: " · "))
        } else {
            if let minutes = result.minutes { parts.append("\(Int(minutes.rounded())) min") }
            if let km = result.distanceKm { parts.append("\(decimal(km)) km") }
            if let pace = result.pace { parts.append("\(Pace.text(pace))/km") }
            if let heart = result.heartAvg { parts.append("\(heart) bpm") }
            if parts.isEmpty, !result.sets.isEmpty {
                parts.append(result.sets.map(setsLine).joined(separator: " · "))
            }
        }
        if let effort = result.effort {
            parts.append("felt \(effort)/10")
        } else if let felt = result.felt {
            parts.append("felt \(felt)")
        }
        return parts.isEmpty ? (session.how ?? "Done") : parts.joined(separator: " · ")
    }

    /// "Squat 3×5 at 80".
    public static func setsLine(_ done: BodyBlock.SetDone) -> String {
        var line = done.exercise
        if let sets = done.sets, let reps = done.reps {
            line += " \(sets)×\(reps)"
        } else if let reps = done.reps {
            line += " \(reps) reps"
        }
        if let load = done.loadKg { line += " at \(decimal(load))" }
        return line
    }

    // MARK: - Planned against done

    /// How done compares with planned.
    public enum Verdict: Sendable, Equatable {
        case onPlan
        /// Faster than planned.
        case quick
        /// Slower than planned.
        case slow
        /// More than planned, such as a higher heart rate or a longer run.
        case over
        /// Less than planned.
        case under

        public var words: String {
            switch self {
            case .onPlan: "on plan"
            case .quick: "a touch quick"
            case .slow: "a touch slow"
            case .over: "over"
            case .under: "under"
            }
        }
    }

    /// One row of planned against done: what, what was planned, what happened, and how they
    /// compare.
    public struct Comparison: Sendable, Equatable, Identifiable {
        public let label: String
        public let planned: String?
        public let done: String?
        public let verdict: Verdict?

        public var id: String { label }
    }

    /// Planned against done, a row for each measure either side has.
    public static func comparison(_ session: BodyBlock.Session) -> [Comparison] {
        let planned = session.planned
        let result = session.result
        var rows: [Comparison] = []
        if planned?.minutes != nil || result?.minutes != nil {
            rows.append(
                Comparison(
                    label: "Time", planned: planned?.minutes.map { "\(Int($0.rounded())) min" },
                    done: result?.minutes.map(clock),
                    verdict: within(result?.minutes, of: planned?.minutes)))
        }
        if planned?.distanceKm != nil || result?.distanceKm != nil {
            rows.append(
                Comparison(
                    label: "Distance",
                    planned: planned?.distanceKm.map { "about \(decimal($0)) km" },
                    done: result?.distanceKm.map { "\(decimal($0)) km" },
                    verdict: within(result?.distanceKm, of: planned?.distanceKm)))
        }
        if planned?.pace != nil || result?.pace != nil {
            let verdict: Verdict? =
                if let pace = result?.pace, let range = planned?.pace {
                    pace < range.lowerBound ? .quick : pace > range.upperBound ? .slow : .onPlan
                } else { nil }
            rows.append(
                Comparison(
                    label: "Pace",
                    planned: planned?.pace.map {
                        "\(Pace.text($0.lowerBound))–\(Pace.text($0.upperBound))"
                    },
                    done: result?.pace.map { "\(Pace.text($0)) /km" }, verdict: verdict))
        }
        if planned?.heartUnder != nil || result?.heartAvg != nil {
            let verdict: Verdict? =
                if let heart = result?.heartAvg, let cap = planned?.heartUnder {
                    heart < cap ? .onPlan : .over
                } else { nil }
            rows.append(
                Comparison(
                    label: "Heart", planned: planned?.heartUnder.map { "under \($0)" },
                    done: result?.heartAvg.map { "\($0) avg" }, verdict: verdict))
        }
        if planned?.effort != nil || result?.felt != nil || result?.effort != nil {
            rows.append(
                Comparison(
                    label: "Felt", planned: planned?.effort,
                    done: result?.felt ?? result?.effort.map { "\($0)/10" }, verdict: nil))
        }
        return rows
    }

    // MARK: - The block's trends

    /// A week's hours: done, and still planned.
    public struct WeekHours: Sendable, Equatable, Identifiable {
        public let number: Int
        public let done: Double
        public let planned: Double
        public let isCurrent: Bool

        public var id: Int { number }
    }

    /// Hours a week through the block, done and planned; `nil` when no session has a length.
    public static func hours(
        _ block: BodyBlock, state: MotionState, now: Date = .now, calendar: Calendar = .current
    ) -> [WeekHours]? {
        let current = currentWeek(of: block, now: now, calendar: calendar)?.number
        let weeks = block.weeks.enumerated().map { index, week in
            let sessions = counted(week)
            let done = sessions.filter { isDone($0, in: state) }.compactMap {
                minutes(of: $0, in: state)
            }
            let planned = sessions.filter { !isDone($0, in: state) }.compactMap {
                plannedMinutes(of: $0)
            }
            return WeekHours(
                number: index + 1, done: done.reduce(0, +) / 60, planned: planned.reduce(0, +) / 60,
                isCurrent: index + 1 == current)
        }
        return weeks.contains { $0.done + $0.planned > 0 } ? weeks : nil
    }

    /// A point on a trend: a day and its value.
    public struct Point: Sendable, Equatable, Identifiable {
        public let date: String
        public let value: Double

        public var id: String { date }
    }

    /// The pace of each run with a pace from a result, in seconds per km, oldest first; `nil`
    /// with fewer than two.
    public static func pace(_ block: BodyBlock, state: MotionState) -> [Point]? {
        let points = block.weeks.flatMap(\.sessions)
            .filter { $0.kind.plain == .run && isDone($0, in: state) }
            .compactMap { session in
                session.result?.pace.map { Point(date: session.date.rawValue, value: Double($0)) }
            }
            .sorted { $0.date < $1.date }
        return points.count >= 2 ? points : nil
    }

    /// The heaviest load recorded for the exercise recorded most often, oldest first: its name and
    /// its points; `nil` unless it was recorded at least twice.
    public static func load(_ block: BodyBlock, state: MotionState) -> (
        exercise: String, points: [Point]
    )? {
        let sessions = block.weeks.flatMap(\.sessions).filter { isDone($0, in: state) }
        let loads = sessions.flatMap { session in
            (session.result?.sets ?? []).compactMap { done in
                done.loadKg.map { (done.exercise, session.date.rawValue, $0) }
            }
        }
        let counts = Dictionary(grouping: loads, by: \.0).mapValues { Set($0.map(\.1)).count }
        guard let exercise = counts.filter({ $0.value >= 2 }).max(by: { $0.value < $1.value })?.key
        else { return nil }
        let points = Dictionary(grouping: loads.filter { $0.0 == exercise }, by: \.1)
            .map { date, sets in Point(date: date, value: sets.map(\.2).max() ?? 0) }
            .sorted { $0.date < $1.date }
        return (exercise, points)
    }

    /// Timed efforts towards the goal, in seconds, oldest first, with the goal; `nil` with fewer
    /// than two or a goal that isn't a time.
    public static func results(_ block: BodyBlock) -> (points: [Point], goal: Double)? {
        guard let target = block.goal?.target.flatMap(Pace.seconds) else { return nil }
        let points = block.results.compactMap { result in
            Pace.seconds(result.result).map { Point(date: result.date, value: Double($0)) }
        }
        return points.count >= 2 ? (points, Double(target)) : nil
    }

    // MARK: - Measures

    /// How long a session took, or is planned to take: done from its result, else as planned.
    public static func minutes(of session: BodyBlock.Session, in state: MotionState) -> Double? {
        if isDone(session, in: state), let minutes = session.result?.minutes { return minutes }
        return plannedMinutes(of: session)
    }

    private static func plannedMinutes(of session: BodyBlock.Session) -> Double? {
        session.planned?.minutes
    }

    /// 150 minutes as "2h 30m", 35 as "35m".
    public static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60
            ? "\(total / 60)h \(String(format: "%02d", total % 60))m" : "\(total)m"
    }

    /// 31.2 minutes as "31:12".
    public static func clock(_ minutes: Double) -> String {
        Pace.text(Int((minutes * 60).rounded()))
    }

    /// 5.2 as "5.2", 5.0 as "5", for kilometres and kilograms.
    public static func decimal(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// Within a tenth of what was planned is on plan.
    private static func within(_ done: Double?, of planned: Double?) -> Verdict? {
        guard let done, let planned, planned > 0 else { return nil }
        let ratio = done / planned
        return ratio > 1.1 ? .over : ratio < 0.9 ? .under : .onPlan
    }

    // MARK: - Days

    /// Today in the device's calendar, as `2026-11-17`.
    public static func day(of now: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A day some days on from another.
    public static func adding(_ days: Int, to day: String) -> String {
        guard let date = noon(day), let moved = utc.date(byAdding: .day, value: days, to: date)
        else {
            return day
        }
        return BodyReading.day(of: moved, in: utc)
    }

    /// A day as noon UTC, so no time zone moves it to the day before.
    public static func noon(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: day + " 12:00")
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func letter(of day: String) -> String {
        guard let date = noon(day) else { return "" }
        return ["S", "M", "T", "W", "T", "F", "S"][utc.component(.weekday, from: date) - 1]
    }
}
