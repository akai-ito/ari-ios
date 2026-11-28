import Foundation

/// What hangs over Kumo's shoulder on the Desk: the moon from the night's dream until you've seen
/// its record, then the sun by day, a low amber sun in the evening, and nothing from midnight until
/// the dream, while Kumo sleeps.
public enum Sky: String, Equatable, Sendable {
    case none, moon, sun, dusk
}

public enum DreamReading {
    /// From this hour the sun is low and amber.
    public static let evening = 19
    /// Kumo sleeps from midnight until this hour, and while it dreams.
    public static let wakes = 6

    /// The sky over Kumo's shoulder now.
    public static func sky(now: Date, state: DreamState?, calendar: Calendar = .current) -> Sky {
        if state?.dreaming != nil { return .none }
        let midnight = calendar.startOfDay(for: now)
        let dreamtTonight = (state?.latest?.endedAt.date ?? .distantPast) >= midnight
        let dreamTime =
            state.flatMap { PlanReading.time($0.time, on: now, calendar: calendar) }
            ?? calendar.date(bySettingHour: 4, minute: 0, second: 0, of: now) ?? now
        // From midnight until tonight's dream, Kumo is asleep and the sky is empty.
        if now < dreamTime, !dreamtTonight { return .none }
        if state?.latest?.isNew == true { return .moon }
        return calendar.component(.hour, from: now) >= evening ? .dusk : .sun
    }

    /// Whether Kumo is asleep on the Desk: from midnight until morning, and while it dreams.
    public static func asleep(now: Date, state: DreamState?, calendar: Calendar = .current)
        -> Bool
    {
        state?.dreaming != nil || calendar.component(.hour, from: now) < wakes
    }

    /// Whether the moon/sun page leads with last night: its record is new, or it was a dream you
    /// asked for today.
    public static func leadsWithDream(_ dream: Dream?, now: Date, calendar: Calendar = .current)
        -> Bool
    {
        guard let dream else { return false }
        if dream.isNew { return true }
        return dream.trigger == .manual && calendar.isDate(dream.endedAt.date, inSameDayAs: now)
    }

    /// A word for each subject, to drift up off Kumo while it dreams: a name where there is one,
    /// such as "Northwind" from "Northwind prep", short enough to read in dots.
    public static func words(from titles: [String], limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for title in titles {
            guard let word = word(from: title), seen.insert(word.lowercased()).inserted else {
                continue
            }
            words.append(word)
            if words.count == limit { break }
        }
        return words
    }

    static func word(from title: String) -> String? {
        let candidates = title.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .map {
                String($0).replacingOccurrences(of: "’s", with: "").replacingOccurrences(
                    of: "'s", with: "")
            }
            .filter { $0.count >= 3 && $0.count <= 9 }
        let names = candidates.filter { $0.first?.isUppercase == true }
        return (names.max { $0.count < $1.count }) ?? candidates.max { $0.count < $1.count }
    }

    /// A memory page's name, as a word on the weave: "Leo" for `memory:people/leo`, "Journal" for a
    /// journal day.
    public static func pageWord(_ page: String) -> String {
        let path = page.split(separator: ":").last.map(String.init) ?? page
        let parts = path.split(separator: "/").map(String.init)
        if parts.first == "journal" { return "Journal" }
        let name = (parts.last ?? path).replacingOccurrences(of: "-", with: " ")
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// What the weave draws, for one dream: the day's conversations coming in as strands, the pages
/// Kumo tied them into, tomorrow's plans as knots on the strand it spins out, and a line for each
/// moment. Built from what the app knows: the day's threads and mail, the server's lines for each
/// step while Kumo dreams, and the record once it's done.
public struct WeaveScene: Equatable, Sendable {
    public struct Page: Equatable, Sendable {
        /// Such as "Leo".
        public let word: String
        /// Under it once it's a page, such as "Monday" for a journal day.
        public let note: String?

        public init(word: String, note: String? = nil) {
            self.word = word
            self.note = note
        }
    }

    public struct Knot: Equatable, Sendable {
        public let at: Date
        public let title: String

        public init(at: Date, title: String) {
            self.at = at
            self.title = title
        }
    }

    /// The day it weaves, such as "Monday".
    public var day: String
    /// Its conversations and mail, each a strand, at most six.
    public var strands: [String]
    /// What it tied them into, at most three.
    public var pages: [Page]
    /// Tomorrow's plans, as knots on its strand, at most three, soonest first.
    public var plans: [Knot]
    /// While the strands come in.
    public var gathering: String
    /// While Kumo ties them, one after another.
    public var tying: [String]
    /// While tomorrow spins out.
    public var tomorrow: [String]
    /// Whether it's from a dream's record, so the pages and plans are what it did.
    public var isRecorded: Bool
    /// While Kumo dreams, the server's line for the step it's on, such as "Tidying Leo".
    public var latest: String?
    /// While Kumo dreams, how far its steps have got: gathering, tying (tidying and the journal)
    /// or tomorrow (planning).
    public var stage: Stage

    public enum Stage: Int, Comparable, Sendable {
        case gathering, tying, tomorrow

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        init(_ group: DreamStepGroup) {
            switch group.shown {
            case .tidying, .journal: self = .tying
            case .planning: self = .tomorrow
            default: self = .gathering
            }
        }
    }

    public init(
        day: String, strands: [String], pages: [Page] = [], plans: [Knot] = [],
        gathering: String, tying: [String], tomorrow: [String], isRecorded: Bool = false,
        latest: String? = nil, stage: Stage = .gathering
    ) {
        self.day = day
        self.strands = strands
        self.pages = pages
        self.plans = plans
        self.gathering = gathering
        self.tying = tying
        self.tomorrow = tomorrow
        self.isRecorded = isRecorded
        self.latest = latest
        self.stage = stage
    }

    /// A scene for a dream, or for one under way when `dream` is `nil`.
    /// - Parameters:
    ///   - day: The weekday it looks back on, such as "Monday".
    ///   - threads: The titles of the day's side threads, newest first.
    ///   - mailRead: How many emails you read or Kumo read for you that day.
    ///   - plans: Kumo's plans now, to find the times of the ones the dream set or moved.
    ///   - comingUp: What's on the calendar, for the items the dream planned.
    ///   - steps: A dream under way's steps so far, oldest first.
    public static func make(
        day: String, threads: [String], mailRead: Int, dream: Dream?, plans: [WakeUp] = [],
        comingUp: [CalendarItem] = [], steps: [DreamStep] = []
    ) -> WeaveScene {
        var strands: [String] = ["Main chat"]
        strands.append(contentsOf: threads.prefix(mailRead > 0 ? 4 : 5))
        if mailRead > 0 { strands.append("Mail · \(mailRead) you read") }
        let threadCount = threads.count + 1
        let threadWord = threadCount == 1 ? "thread" : "threads"
        var gathering = "Gathering \(day): \(spelled(threadCount)) \(threadWord)"
        if mailRead > 0 {
            let mailWord = mailRead == 1 ? "email" : "emails"
            gathering += ", \(spelled(mailRead)) \(mailWord) you read."
        } else {
            gathering += "."
        }

        guard let dream else {
            // Live, the server's own lines: the weave reaches as far as its steps have.
            let lines = { (stage: Stage) in
                steps.filter { Stage($0.group) == stage }.map(\.text)
            }
            let tying = lines(.tying)
            let tomorrow = lines(.tomorrow)
            return WeaveScene(
                day: day, strands: strands, gathering: lines(.gathering).last ?? gathering,
                tying: tying.isEmpty ? ["Sorting through \(day).", "Tying them into one."] : tying,
                tomorrow: tomorrow.isEmpty ? ["Putting tomorrow in order."] : tomorrow,
                latest: steps.last?.text, stage: steps.map { Stage($0.group) }.max() ?? .gathering)
        }

        var seenPages = Set<String>()
        let pages: [Page] = dream.lines.compactMap { line in
            guard let page = line.page, line.group.shown != .planned else { return nil }
            let word = DreamReading.pageWord(page)
            guard seenPages.insert(word).inserted else { return nil }
            return Page(word: word, note: word == "Journal" ? day : nil)
        }

        var knots: [Knot] = []
        for line in dream.lines where line.group.shown == .planned && !line.undone {
            if let id = line.wakeUp, let plan = plans.first(where: { $0.id == id }) {
                knots.append(Knot(at: plan.at.date, title: plan.shownTitle))
            } else if let id = line.event, let item = comingUp.first(where: { $0.id == id }),
                let start = item.start.instant
            {
                knots.append(Knot(at: start, title: item.title))
            }
        }
        knots.sort { $0.at < $1.at }

        let told = dream.lines.filter { $0.group.shown != .planned }.map(\.text)
        let planned = dream.lines.filter { $0.group.shown == .planned }.map(\.text)
        return WeaveScene(
            day: day, strands: strands, pages: Array(pages.prefix(3)),
            plans: Array(knots.prefix(3)), gathering: gathering,
            tying: told.isEmpty ? ["Tying them into one."] : Array(told.prefix(3)),
            tomorrow: planned.isEmpty
                ? [dream.headline ?? "Tomorrow, in order."] : Array(planned.prefix(2)),
            isRecorded: true)
    }

    /// "nine" for 9; numbers past twelve as digits.
    static func spelled(_ number: Int) -> String {
        let words = [
            "no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve",
        ]
        return number < words.count ? words[number] : "\(number)"
    }
}
