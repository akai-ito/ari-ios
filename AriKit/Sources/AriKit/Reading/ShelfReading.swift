import Foundation

/// How the Library lays out a shelf: the pages Ari touched lately, then everyone; and the journal's
/// days by month.
public enum ShelfReading {
    /// The pages Ari changed in the last two weeks, newest first, up to five, leaving out a bulk
    /// change: when most of a shelf changed within the same hour, as an import does, those changes
    /// say nothing about what's going on. None when more than half the shelf changed lately, since
    /// then lately doesn't stand out from everyone.
    public static func lately(_ pages: [PageSummary], now: Date = .now) -> [PageSummary] {
        let changed = pages.compactMap { page in page.changedAt.map { (page, $0.date) } }
        let recent = changed.filter { now.timeIntervalSince($0.1) < 14 * 86_400 }
        let hours = Dictionary(grouping: changed) { Int($0.1.timeIntervalSince1970 / 3_600) }
        let bulk = hours.values.filter { $0.count >= 5 && $0.count * 2 >= pages.count }
            .flatMap { $0.map(\.0.address) }
        let fresh = recent.filter { !bulk.contains($0.0.address) }
        guard fresh.count * 2 <= pages.count else { return [] }
        return
            fresh
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map(\.0)
    }

    /// Everyone on a shelf, A to Z as people read it.
    public static func everyone(_ pages: [PageSummary]) -> [PageSummary] {
        pages.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// People by the circle Ari keeps for each, closest first: partner and family, then friends, then
    /// work, then any other circle Ari uses, A to Z. People without a circle yet come last, as `nil`.
    /// Each circle's people read A to Z.
    public static func circles(_ pages: [PageSummary]) -> [(circle: String?, pages: [PageSummary])]
    {
        let closest = ["partner", "family", "close", "friends", "work"]
        let grouped = Dictionary(grouping: pages) { $0.circle?.lowercased() }
        let named = grouped.keys.compactMap(\.self).sorted { a, b in
            let first = closest.firstIndex(of: a) ?? closest.count
            let second = closest.firstIndex(of: b) ?? closest.count
            return first != second ? first < second : a < b
        }
        var circles = named.map { (circle: Optional($0), pages: everyone(grouped[$0] ?? [])) }
        if let unplaced = grouped[nil], !unplaced.isEmpty {
            circles.append((circle: nil, pages: everyone(unplaced)))
        }
        return circles
    }

    /// A journal page's day, from its address: `memory:journal/2026-10-26`.
    public static func day(of page: PageSummary) -> DateComponents? {
        guard let last = page.address.rawValue.split(separator: "/").last else { return nil }
        let parts = last.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The journal's days, newest month first, each month's days newest first.
    public static func months(_ pages: [PageSummary]) -> [Month] {
        let days = pages.compactMap { page in day(of: page).map { (page, $0) } }
        let grouped = Dictionary(grouping: days) { MonthKey(year: $0.1.year!, month: $0.1.month!) }
        return grouped.keys.sorted(by: >).map { key in
            Month(
                year: key.year, month: key.month,
                days: grouped[key]!.sorted { $0.1.day! > $1.1.day! }.map {
                    Day(page: $0.0, day: $0.1.day!)
                })
        }
    }

    public struct Month: Equatable, Sendable, Identifiable {
        public let year: Int
        public let month: Int
        public let days: [Day]
        public var id: String { "\(year)-\(month)" }
    }

    public struct Day: Equatable, Sendable {
        public let page: PageSummary
        public let day: Int
    }

    private struct MonthKey: Hashable, Comparable {
        let year: Int
        let month: Int
        static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }
    }
}
