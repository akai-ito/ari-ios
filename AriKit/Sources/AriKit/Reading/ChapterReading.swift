import Foundation

/// How the Library says a chapter's when, where it came from and which pages it links to, and
/// when Kumo learnt something, in words rather than dates.
public enum ChapterReading {
    /// When, for a chapter's card: "Since 3 Nov · still going", or the month it happened in and how
    /// long: "October · six days", "June – July · two months". The year shows when it isn't this
    /// one.
    public static func when(
        began: LocalTime, ended: LocalTime?, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        guard let ended else {
            return "Since \(day(began, short: true, now: now, calendar: calendar)) · still going"
        }
        let start = began.date(in: calendar)
        let end = ended.date(in: calendar)
        let months =
            calendar.isDate(start, equalTo: end, toGranularity: .month)
            ? month(start, now: now, calendar: calendar)
            : "\(month(start, now: now, calendar: calendar, withYear: false)) – \(month(end, now: now, calendar: calendar))"
        return "\(months) · \(length(from: began, to: ended, calendar: calendar))"
    }

    /// When, for a chapter's page: "4–9 October · six days", "28 September – 3 October · six days",
    /// or "Since 3 November · still going".
    public static func span(
        began: LocalTime, ended: LocalTime?, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        guard let ended else {
            return "Since \(day(began, short: false, now: now, calendar: calendar)) · still going"
        }
        let start = began.date(in: calendar)
        let end = ended.date(in: calendar)
        let dates: String
        if calendar.isDate(start, inSameDayAs: end) {
            dates = day(began, short: false, now: now, calendar: calendar)
        } else if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            dates =
                "\(calendar.component(.day, from: start))–\(day(ended, short: false, now: now, calendar: calendar))"
        } else {
            let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
            let first = start.formatted(
                style(calendar).day().month(.wide).year(sameYear ? .omitted : .defaultDigits))
            dates = "\(first) – \(day(ended, short: false, now: now, calendar: calendar))"
        }
        return "\(dates) · \(length(from: began, to: ended, calendar: calendar))"
    }

    /// How long it lasted, in words: "one day", "six days", "three weeks", "two months", "a year".
    public static func length(
        from began: LocalTime, to ended: LocalTime, calendar: Calendar = .current
    )
        -> String
    {
        let start = began.date(in: calendar)
        let end = ended.date(in: calendar)
        let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        switch days {
        case ..<14: return count(days, "day")
        case ..<60: return count(Int((Double(days) / 7).rounded()), "week")
        case ..<365: return count(Int((Double(days) / 30.4).rounded()), "month")
        default:
            let years = Int((Double(days) / 365).rounded())
            return years == 1 ? "a year" : count(years, "year")
        }
    }

    /// Where a chapter came from: "Kumo noticed this chapter on 10 October, from your journal, 86
    /// photos and what you told it." Only what it drew on, as the server counted it.
    public static func provenance(
        _ facts: ChapterFacts, lead: String, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        var sources: [String] = []
        if facts.drawnFrom.journalDays > 0 { sources.append("your journal") }
        if facts.drawnFrom.photos > 0 { sources.append(count(facts.drawnFrom.photos, "photo")) }
        sources.append("what you told it")
        let from =
            sources.count == 1
            ? sources[0] : sources.dropLast().joined(separator: ", ") + " and " + sources.last!
        let noticed =
            facts.noticed.map { " on \(day($0, short: false, now: now, calendar: calendar))" } ?? ""
        return "\(lead) noticed this chapter\(noticed), from \(from)."
    }

    /// A chapter's links as chips: each page by its title, and the journal days it draws on as one,
    /// "Journal, 4–9 Oct", which opens the first of them.
    public static func chips(_ links: [MemoryLink], calendar: Calendar = .current, now: Date = .now)
        -> [Chip]
    {
        let days = links.compactMap { link in
            journalDay(link.address).map { (link, $0) }
        }
        var chips: [Chip] = []
        var placedDays = false
        for link in links {
            guard journalDay(link.address) != nil else {
                chips.append(Chip(title: link.title, address: link.address))
                continue
            }
            guard !placedDays, let first = days.min(by: { $0.1.rawValue < $1.1.rawValue }),
                let last = days.max(by: { $0.1.rawValue < $1.1.rawValue })
            else { continue }
            placedDays = true
            chips.append(
                Chip(
                    title: "Journal, \(shortSpan(first.1, last.1, calendar: calendar, now: now))",
                    address: first.0.address))
        }
        return chips
    }

    /// A linked page, or the journal days a chapter draws on, as one chip.
    public struct Chip: Sendable, Equatable, Identifiable {
        public let title: String
        public let address: PageAddress
        public var id: PageAddress { address }

        public init(title: String, address: PageAddress) {
            self.title = title
            self.address = address
        }
    }

    /// When Kumo learnt something: "Today", "Yesterday", the weekday within the week, then the
    /// date, "12 Nov".
    public static func learnt(_ time: Timestamp, now: Date = .now, calendar: Calendar = .current)
        -> String
    {
        let date = time.date
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
            ).day ?? 0
        if days == 1 { return "Yesterday" }
        if (2..<7).contains(days) { return date.formatted(style(calendar).weekday(.wide)) }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(
            style(calendar).day().month(.abbreviated).year(sameYear ? .omitted : .defaultDigits))
    }

    /// How fresh a page is, for Now's card: "this morning", "this afternoon", "this evening",
    /// "yesterday", the weekday within the week, then the date.
    public static func freshness(_ time: Timestamp, now: Date = .now, calendar: Calendar = .current)
        -> String
    {
        let date = time.date
        guard calendar.isDate(date, inSameDayAs: now) else {
            let when = learnt(time, now: now, calendar: calendar)
            return when == "Yesterday" ? "yesterday" : when
        }
        switch calendar.component(.hour, from: date) {
        case ..<12: return "this morning"
        case ..<18: return "this afternoon"
        default: return "this evening"
        }
    }

    // MARK: - Words

    /// Dates as `calendar` reads them: its locale and its time zone, so a day is never a day off.
    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
    }

    private static let numbers = [
        "no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve",
    ]

    private static func count(_ value: Int, _ noun: String) -> String {
        let number = numbers.indices.contains(value) ? numbers[value] : String(value)
        return value == 1 ? "\(number) \(noun)" : "\(number) \(noun)s"
    }

    private static func day(_ day: LocalTime, short: Bool, now: Date, calendar: Calendar) -> String
    {
        let date = day.date(in: calendar)
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(
            style(calendar).day().month(short ? .abbreviated : .wide)
                .year(sameYear ? .omitted : .defaultDigits))
    }

    private static func month(_ date: Date, now: Date, calendar: Calendar, withYear: Bool = true)
        -> String
    {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return date.formatted(
            style(calendar).month(.wide).year(sameYear || !withYear ? .omitted : .defaultDigits))
    }

    private static func shortSpan(
        _ first: LocalTime, _ last: LocalTime, calendar: Calendar, now: Date
    )
        -> String
    {
        let start = first.date(in: calendar)
        let end = last.date(in: calendar)
        if calendar.isDate(start, inSameDayAs: end) {
            return day(first, short: true, now: now, calendar: calendar)
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return
                "\(calendar.component(.day, from: start))–\(day(last, short: true, now: now, calendar: calendar))"
        }
        return
            "\(day(first, short: true, now: now, calendar: calendar)) – \(day(last, short: true, now: now, calendar: calendar))"
    }

    private static func journalDay(_ address: PageAddress) -> LocalTime? {
        guard address.rawValue.hasPrefix("memory:journal/") else { return nil }
        return LocalTime(String(address.rawValue.dropFirst("memory:journal/".count)))
    }
}
