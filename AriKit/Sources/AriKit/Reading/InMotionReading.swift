import Foundation

/// How In motion reads: six sections in a fixed order, each loud inside, then History. Kumo judges
/// what's loud; Ari only follows it. The loudest thing in a section is big, the rest are rows, and
/// the quiet ones fold into "+ N quieter".
public enum InMotionReading {
    /// One section, as it shows.
    public struct Section: Sendable, Equatable, Identifiable {
        public let kind: MotionSection
        /// The thing that's big, with its picture: the loudest that isn't quiet.
        public let lead: Motion?
        /// The others that aren't quiet, as rows.
        public let rows: [Motion]
        /// The quiet ones, folded away.
        public let quieter: [Motion]

        public var id: MotionSection { kind }
        /// Everything in it, loudest first.
        public var all: [Motion] { (lead.map { [$0] } ?? []) + rows + quieter }
        public var isEmpty: Bool { all.isEmpty }
    }

    /// Every section, in its fixed order, even an empty one, from what's going on.
    public static func sections(_ going: [Motion]) -> [Section] {
        MotionSection.allCases.map { kind in
            let mine = ordered(going.filter { $0.section == kind && $0.status != .done })
            let shown = mine.filter { $0.salience != .quiet }
            return Section(
                kind: kind, lead: shown.first, rows: Array(shown.dropFirst()),
                quieter: mine.filter { $0.salience == .quiet })
        }
    }

    /// Loudest first, then the most recently changed.
    public static func ordered(_ motions: [Motion]) -> [Motion] {
        motions.sorted { a, b in
            if a.salience.rank != b.salience.rank { return a.salience.rank < b.salience.rank }
            return a.changedAt.date > b.changedAt.date
        }
    }

    /// A month of History.
    public struct Month: Sendable, Equatable, Identifiable {
        /// Its first day, for its name.
        public let start: Date
        /// What ended in it, newest first.
        public let items: [Motion]

        public var id: Date { start }
    }

    /// What ended, newest first, by month: never a copy, a test or small admin kept elsewhere.
    public static func history(_ motions: [Motion], calendar: Calendar = .current) -> [Month] {
        let ended = motions.filter(\.isInHistory).sorted { endedAt($0) > endedAt($1) }
        let months = Dictionary(grouping: ended) { motion in
            calendar.dateInterval(of: .month, for: endedAt(motion))?.start ?? endedAt(motion)
        }
        return months.keys.sorted(by: >).map { Month(start: $0, items: months[$0] ?? []) }
    }

    /// How many ended each way, in History's order, leaving out a way none did.
    public static func tally(_ motions: [Motion]) -> [(outcome: MotionOutcome, count: Int)] {
        let ended = motions.filter(\.isInHistory)
        let known = MotionOutcome.shown.map { outcome in
            (outcome, ended.filter { $0.outcome == outcome }.count)
        }
        let untold = ended.filter {
            !MotionOutcome.shown.contains($0.outcome ?? .init(rawValue: ""))
        }
        return (known + [(MotionOutcome(rawValue: "ended"), untold.count)]).filter { $0.1 > 0 }
    }

    /// When it ended, or last changed for one with no end recorded.
    public static func endedAt(_ motion: Motion) -> Date {
        (motion.doneAt ?? motion.changedAt).date
    }
}

/// How a role reads: where it is on the pipeline, and when it got to each stage.
public enum CareerReading {
    /// Its place on the pipeline's line, from 0 (a lead) to 3 (an offer). An ended role sits where
    /// it got to.
    public static func position(of career: Career) -> Int {
        if let index = Career.Stage.pipeline.firstIndex(of: career.stage) { return index }
        return Career.Stage.pipeline.lastIndex { career.stages[$0] != nil } ?? 0
    }

    /// The day it reached each stage on the line, short, such as "2 Nov"; `nil` for one not
    /// reached or not dated.
    public static func dates(of career: Career, locale: Locale = .current) -> [String?] {
        Career.Stage.pipeline.map { stage in
            career.stages[stage].map { short($0, locale: locale) }
        }
    }

    /// "7 Dec".
    public static func short(_ time: LocalTime, locale: Locale = .current) -> String {
        format(time, template: "d MMM", locale: locale)
    }

    /// "Mon 7 Dec".
    public static func day(_ time: LocalTime, locale: Locale = .current) -> String {
        format(time, template: "EEE d MMM", locale: locale)
    }

    /// "14:00".
    public static func time(_ time: LocalTime, locale: Locale = .current) -> String? {
        time.isDay ? nil : format(time, template: "HH:mm", locale: locale)
    }

    /// "today", "tomorrow", "in 16 days", or "3 days ago".
    public static func countdown(
        to time: LocalTime, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        let start = calendar.startOfDay(for: now)
        let then = calendar.startOfDay(for: time.date(in: calendar))
        let days = calendar.dateComponents([.day], from: start, to: then).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case ..<0: return "\(-days) days ago"
        default: return "in \(days) days"
        }
    }

    private static func format(_ time: LocalTime, template: String, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: time.date())
    }
}
