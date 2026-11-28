import Foundation

/// A diary of the trail's costly part, kept on the phone so the first weeks' battery can be
/// checked: each time live GPS starts or stops, and why, with the battery then. Three weeks are
/// kept; Settings › Places shows today's total.
public struct LiveLog: Sendable {
    public struct Entry: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable {
            case liveOn = "live_on"
            case liveOff = "live_off"
            /// The mode changed: `detail` is the new one.
            case mode
            /// A visit or significant change woke Ito in the background.
            case woke
        }

        public let at: Date
        public let kind: Kind
        /// Why: "departed", "significant change", "stationary", "arrived", "low power"…
        public let detail: String
        /// The battery from 0 to 1, when known.
        public let battery: Double?
        public let lowPower: Bool

        public init(
            at: Date, kind: Kind, detail: String, battery: Double? = nil, lowPower: Bool = false
        ) {
            self.at = at
            self.kind = kind
            self.detail = detail
            self.battery = battery
            self.lowPower = lowPower
        }
    }

    /// One day's live GPS: how long it ran, in how many runs.
    public struct Day: Sendable, Equatable {
        public let live: TimeInterval
        public let runs: Int
    }

    public let file: URL
    public static let keptFor: TimeInterval = 21 * 86_400

    public init(file: URL) {
        self.file = file
    }

    public static func applicationSupport() throws -> LiveLog {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return LiveLog(file: support.appending(path: "Trail-live-log.json"))
    }

    public func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    public func add(_ entry: Entry) {
        let cutoff = entry.at.addingTimeInterval(-Self.keptFor)
        var all = entries().filter { $0.at >= cutoff }
        all.append(entry)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }

    /// Live GPS on the day `day` falls in, up to `now` for a run still going.
    public func day(_ day: Date, calendar: Calendar = .current, now: Date = .now) -> Day {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return Self.day(entries(), from: start, to: min(end, now))
    }

    static func day(_ entries: [Entry], from start: Date, to end: Date) -> Day {
        var live: TimeInterval = 0
        var runs = 0
        var since: Date?
        for entry in entries.sorted(by: { $0.at < $1.at }) {
            switch entry.kind {
            case .liveOn where since == nil:
                since = entry.at
            case .liveOff:
                if let began = since {
                    (live, runs) = add(began, entry.at, start, end, live, runs)
                }
                since = nil
            default:
                continue
            }
        }
        if let began = since { (live, runs) = add(began, end, start, end, live, runs) }
        return Day(live: live, runs: runs)
    }

    private static func add(
        _ began: Date, _ ended: Date, _ start: Date, _ end: Date, _ live: TimeInterval, _ runs: Int
    ) -> (TimeInterval, Int) {
        let from = max(began, start)
        let to = min(ended, end)
        guard to > from else { return (live, runs) }
        return (live + to.timeIntervalSince(from), runs + 1)
    }
}
