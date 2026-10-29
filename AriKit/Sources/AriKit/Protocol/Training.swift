import Foundation

/// A training block towards a goal, such as a sub-20 5K: the goal, your results so far, and every
/// week's sessions, first to last. Ari writes it; your ticks on sessions are in the thing's state.
public struct Training: Sendable, Equatable, Decodable {
    public let goal: Goal
    /// Every week of the block, first to last.
    public let weeks: [Week]
    /// Results towards the goal, oldest first.
    public let results: [Result]

    public init(goal: Goal, weeks: [Week] = [], results: [Result] = []) {
        self.goal = goal
        self.weeks = weeks
        self.results = results
    }

    public struct Goal: Sendable, Equatable, Decodable {
        /// Such as "Sub-20 5K".
        public let title: String
        /// Such as "19:59".
        public let target: String
        /// The day it's for, such as `2026-11-30`.
        public let by: String?

        public init(title: String, target: String, by: String? = nil) {
            self.title = title
            self.target = target
            self.by = by
        }
    }

    /// One week of the block, its sessions in order.
    public struct Week: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        /// Its first day, such as `2026-10-26`.
        public let start: String
        /// Such as "Speed".
        public let focus: String?
        /// A line from Ari on the week.
        public let note: String?
        public let sessions: [Session]

        public init(
            id: String, start: String, focus: String? = nil, note: String? = nil,
            sessions: [Session] = []
        ) {
            self.id = id
            self.start = start
            self.focus = focus
            self.note = note
            self.sessions = sessions
        }
    }

    /// One session in a week.
    public struct Session: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        /// Such as `2026-10-28`.
        public let date: String
        public let kind: SessionKind
        /// Such as "Intervals".
        public let title: String
        /// Such as "6 × 800 m at 3:50/km · 90 s jog · 2 km warm-up".
        public let detail: String?
        /// How Ari wrote it; your tick, in the state, wins.
        public let done: Bool
        /// How it went, as you told Ari.
        public let how: String?

        public init(
            id: String, date: String, kind: SessionKind, title: String, detail: String? = nil,
            done: Bool = false, how: String? = nil
        ) {
            self.id = id
            self.date = date
            self.kind = kind
            self.title = title
            self.detail = detail
            self.done = done
            self.how = how
        }
    }

    /// A result towards the goal, such as a timed 5K.
    public struct Result: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let date: String
        /// Such as "20:41".
        public let result: String
        public let note: String?

        public init(id: String, date: String, result: String, note: String? = nil) {
            self.id = id
            self.date = date
            self.result = result
            self.note = note
        }
    }
}

/// What kind of session: an easy run, intervals, a rest day.
public struct SessionKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let easy = SessionKind(rawValue: "easy")
    public static let intervals = SessionKind(rawValue: "intervals")
    public static let tempo = SessionKind(rawValue: "tempo")
    public static let long = SessionKind(rawValue: "long")
    public static let strength = SessionKind(rawValue: "strength")
    public static let race = SessionKind(rawValue: "race")
    public static let rest = SessionKind(rawValue: "rest")
    public static let known = [easy, intervals, tempo, long, strength, race, rest]
}
