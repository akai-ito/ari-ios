import Foundation

/// How a training block reads: the week you're in, today's session, your best and how far is left.
/// Its days are your own, in the device's calendar. Your ticks, in the thing's state, win over how
/// Ari wrote a session.
public enum TrainingReading {
    /// The sessions' list name in the state, whichever week a session is in.
    public static let sessionsList = "sessions"

    /// Whether a session is done: your tick if you've made one, otherwise how Ari wrote it.
    public static func isDone(_ session: Training.Session, in state: MotionState) -> Bool {
        state[sessionsList]?[session.id]?.done ?? session.done
    }

    /// The week you're in, numbered through the block from 1; before the block, its first week, and
    /// after it, its last.
    public static func currentWeek(
        of training: Training, now: Date = .now, calendar: Calendar = .current
    ) -> (number: Int, week: Training.Week)? {
        let today = day(of: now, in: calendar)
        let index =
            training.weeks.lastIndex { $0.start <= today } ?? (training.weeks.isEmpty ? nil : 0)
        return index.map { ($0 + 1, training.weeks[$0]) }
    }

    /// Today's session, if there is one.
    public static func today(
        in training: Training, now: Date = .now, calendar: Calendar = .current
    ) -> Training.Session? {
        let today = day(of: now, in: calendar)
        return training.weeks.lazy.flatMap(\.sessions).first { $0.date == today }
    }

    /// Whether a session is today's.
    public static func isToday(
        _ session: Training.Session, now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        session.date == day(of: now, in: calendar)
    }

    /// What the pinned line and In motion say: "Sub-20 5K", "Week 6 of 10", and today's session,
    /// "Intervals today", once done "Intervals done".
    public static func line(
        _ training: Training, state: MotionState, now: Date = .now,
        calendar: Calendar = .current
    ) -> (name: String, when: String?, today: String?) {
        let week = currentWeek(of: training, now: now, calendar: calendar).map {
            "Week \($0.number) of \(training.weeks.count)"
        }
        let today = Self.today(in: training, now: now, calendar: calendar).map { session in
            session.kind == .rest
                ? "Rest today"
                : "\(session.title) \(isDone(session, in: state) ? "done" : "today")"
        }
        return (training.goal.title, week, today)
    }

    /// How much of the block is done, from 0 to 1: its sessions other than rest days.
    public static func progress(_ training: Training, state: MotionState) -> Double? {
        let sessions = training.weeks.flatMap(\.sessions).filter { $0.kind != .rest }
        guard !sessions.isEmpty else { return nil }
        return Double(sessions.filter { isDone($0, in: state) }.count) / Double(sessions.count)
    }

    /// The best result so far: the fastest when the target is a time to get under, otherwise the
    /// highest. `nil` before any result, or for results that aren't numbers or times.
    public static func best(_ training: Training) -> Training.Result? {
        let measured = training.results.compactMap { result in
            value(result.result).map { (result, $0) }
        }
        guard let first = measured.first?.1, let target = value(training.goal.target) else {
            return nil
        }
        let lowerIsBetter = target < first
        return measured.min { lowerIsBetter ? $0.1 < $1.1 : $0.1 > $1.1 }?.0
    }

    /// How far the best is from the goal: "42 s to go", "1 min 5 s to go", or "Goal reached".
    public static func toGo(_ training: Training) -> String? {
        guard let best = best(training), let value = value(best.result),
            let first = training.results.first.flatMap({ Self.value($0.result) }),
            let target = Self.value(training.goal.target)
        else { return nil }
        let lowerIsBetter = target < first
        let gap = lowerIsBetter ? value - target : target - value
        guard gap > 0 else { return "Goal reached" }
        guard isTime(training.goal.target) else { return nil }
        let seconds = Int(gap.rounded())
        return seconds < 60
            ? "\(seconds) s to go"
            : "\(seconds / 60) min" + (seconds % 60 == 0 ? "" : " \(seconds % 60) s") + " to go"
    }

    /// A result as a number: a time such as "20:41" or "1:02:03" in seconds, or a plain number.
    public static func value(_ text: String) -> Double? {
        if isTime(text) {
            return text.split(separator: ":").reduce(0.0) { total, part in
                total * 60 + (Double(part) ?? .nan)
            }
        }
        return Double(text.trimmingCharacters(in: .whitespaces))
    }

    /// The goal's day and the week you're in: "By 30 November · week 6 of 10".
    public static func subtitle(
        _ training: Training, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var parts: [String] = []
        if let by = training.goal.by, let date = date(by) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.setLocalizedDateFormatFromTemplate("d MMMM")
            parts.append("By \(formatter.string(from: date))")
        }
        if let week = currentWeek(of: training, now: now, calendar: calendar) {
            parts.append("week \(week.number) of \(training.weeks.count)")
        }
        return parts.joined(separator: " · ")
    }

    /// A result's day, for the trend.
    public static func date(of result: Training.Result) -> Date? {
        date(result.date)
    }

    /// A session's weekday, short: "Wed".
    public static func weekday(of session: Training.Session, locale: Locale = .current) -> String {
        guard let date = date(session.date) else { return session.date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    // MARK: - Days

    private static func isTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        return (2...3).contains(parts.count)
            && parts.allSatisfy { !$0.isEmpty && Double($0) != nil }
    }

    /// Today in the device's calendar, as `2026-10-28`.
    private static func day(of now: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A day, as noon UTC, so no time zone moves it to the day before.
    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text + " 12:00")
    }
}
