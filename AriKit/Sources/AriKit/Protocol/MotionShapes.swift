import Foundation

// The shapes of 0.19's kinds of thing in motion (a role, a training block, a project, something
// being learnt, and something with no shape yet), and what every kind can hold besides: Kumo's
// notes, why its plan changed, and once it's ended, its story. Kumo writes all of it.

/// How much a thing matters to you now, by Kumo's judgement: loud is big in its section, normal is
/// a row, quiet folds into "+ N quieter". A value Ari doesn't know shows as normal.
public struct Salience: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let loud = Salience(rawValue: "loud")
    public static let normal = Salience(rawValue: "normal")
    public static let quiet = Salience(rawValue: "quiet")
    public static let known = [loud, normal, quiet]

    /// Its place in a section, loudest first.
    public var rank: Int {
        switch self {
        case .loud: 0
        case .quiet: 2
        default: 1
        }
    }
}

/// How a thing ended: ending it isn't achieving it. A copy, a test and small admin kept elsewhere
/// never show. A value Ari doesn't know shows as ended.
public struct MotionOutcome: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let achieved = MotionOutcome(rawValue: "achieved")
    /// A goal missed, such as a time not run.
    public static let notMet = MotionOutcome(rawValue: "not_met")
    /// Stopped by choice.
    public static let letGo = MotionOutcome(rawValue: "let_go")
    /// Went into another thing, named by `mergedInto`.
    public static let merged = MotionOutcome(rawValue: "merged")
    /// A copy of another thing: never shown.
    public static let duplicate = MotionOutcome(rawValue: "duplicate")
    /// A test: never shown.
    public static let test = MotionOutcome(rawValue: "test")
    /// Small admin that lives on the Desk or in Kumo's plans now: never shown.
    public static let elsewhere = MotionOutcome(rawValue: "elsewhere")
    public static let known = [achieved, notMet, letGo, merged, duplicate, test, elsewhere]

    /// Whether History shows it. One Ari doesn't know shows, as ended.
    public var isShown: Bool { ![.duplicate, .test, .elsewhere].contains(self) }

    /// The outcomes History counts, in its order.
    public static let shown = [achieved, notMet, letGo, merged]

    /// "Achieved", "Not met", "Let go", "Merged", or "Ended".
    public var name: String {
        switch self {
        case .achieved: "Achieved"
        case .notMet: "Not met"
        case .letGo: "Let go"
        case .merged: "Merged"
        default: "Ended"
        }
    }
}

/// In motion's sections, always in this order. 0.18's kinds sit where they belong until Kumo
/// reshapes them, and a kind Ari doesn't know sits in Other.
public enum MotionSection: String, CaseIterable, Sendable, Identifiable {
    case career, body, trips, projects, learning, other

    public var id: String { rawValue }

    /// "Career", "Body", "Trips", …
    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What every kind can hold besides its own shape: Kumo's notes, why its plan changed, and how it
/// ended.
public struct MotionExtras: Sendable, Equatable, Decodable {
    /// Kumo's working notes, folded at the bottom of the thing's page.
    public let notes: [MotionNote]
    /// Why the plan changed, newest first.
    public let reasons: [MotionReason]
    /// How it ended, once it has.
    public let story: MotionStory?

    public static let none = MotionExtras()

    public init(notes: [MotionNote] = [], reasons: [MotionReason] = [], story: MotionStory? = nil) {
        self.notes = notes
        self.reasons = reasons
        self.story = story
    }

    enum CodingKeys: String, CodingKey { case notes, reasons, story }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = c.lenientList(MotionNote.self, forKey: .notes)
        reasons = c.lenientList(MotionReason.self, forKey: .reasons)
        story = (try? c.decodeIfPresent(MotionStory.self, forKey: .story)) ?? nil
    }
}

/// One of Kumo's working notes: where a fact came from, what it's unsure of or guessing, how the
/// thing got here, or the ids it finds things by. Yours to read, never inline.
public struct MotionNote: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let tag: Tag
    public let text: String
    /// When Kumo learnt it.
    public let at: LocalTime?

    public init(id: String, tag: Tag, text: String, at: LocalTime? = nil) {
        self.id = id
        self.tag = tag
        self.text = text
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case id, tag, text, at }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tag = (try? c.decode(Tag.self, forKey: .tag)) ?? Tag(rawValue: "")
        text = try c.decode(String.self, forKey: .text)
        at = (try? c.decodeIfPresent(LocalTime.self, forKey: .at)) ?? nil
    }

    /// What kind of note. One Ari doesn't know shows as a plain note.
    public struct Tag: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let source = Tag(rawValue: "source")
        public static let unsure = Tag(rawValue: "unsure")
        public static let guess = Tag(rawValue: "guess")
        public static let history = Tag(rawValue: "history")
        public static let ids = Tag(rawValue: "ids")
        public static let known = [source, unsure, guess, history, ids]

        /// "Source", "Unsure", "Guess", "History", "IDs", or "Note".
        public var name: String {
            switch self {
            case .source: "Source"
            case .unsure: "Unsure"
            case .guess: "Guess"
            case .history: "History"
            case .ids: "IDs"
            default: "Note"
            }
        }
    }
}

/// Why the plan changed: "Moved Thursday's run to Saturday" because "5h sleep on Wednesday".
public struct MotionReason: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let date: LocalTime
    public let change: String
    public let because: String?

    public init(id: String, date: LocalTime, change: String, because: String? = nil) {
        self.id = id
        self.date = date
        self.change = change
        self.because = because
    }
}

/// How a thing ended, told short: what happened, what was learnt, and what followed.
public struct MotionStory: Sendable, Equatable, Decodable {
    public let happened: String
    public let learnt: [String]
    /// What came next, in a line.
    public let followed: String?
    /// The thing that came next, to open.
    public let followedBy: MotionID?

    public init(
        happened: String, learnt: [String] = [], followed: String? = nil,
        followedBy: MotionID? = nil
    ) {
        self.happened = happened
        self.learnt = learnt
        self.followed = followed
        self.followedBy = followedBy
    }

    enum CodingKeys: String, CodingKey {
        case happened, learnt, followed
        case followedBy = "followed_by"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        happened = try c.decode(String.self, forKey: .happened)
        learnt = (try? c.decodeIfPresent([String].self, forKey: .learnt)) ?? []
        followed = try c.decodeIfPresent(String.self, forKey: .followed)
        followedBy = try c.decodeIfPresent(MotionID.self, forKey: .followedBy)
    }
}

/// Something to open behind a button, such as the invite or the posting.
public struct MotionLink: Sendable, Equatable, Decodable {
    /// Such as "The invite".
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}

/// The next step, with when and a link where it has them.
public struct MotionNext: Sendable, Equatable, Decodable {
    public let text: String
    public let at: LocalTime?
    public let end: LocalTime?
    /// A line more, such as "With an engineer from the agents team".
    public let detail: String?
    public let link: MotionLink?

    public init(
        text: String, at: LocalTime? = nil, end: LocalTime? = nil, detail: String? = nil,
        link: MotionLink? = nil
    ) {
        self.text = text
        self.at = at
        self.end = end
        self.detail = detail
        self.link = link
    }

    enum CodingKeys: String, CodingKey { case text, at, end, detail, link }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        at = (try? c.decodeIfPresent(LocalTime.self, forKey: .at)) ?? nil
        end = (try? c.decodeIfPresent(LocalTime.self, forKey: .end)) ?? nil
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        link = (try? c.decodeIfPresent(MotionLink.self, forKey: .link)) ?? nil
    }
}

// MARK: - Career

/// One role in your career pipeline. Every role is its own thing, in exactly one stage.
public struct Career: Sendable, Equatable, Decodable {
    /// Such as "Northwind".
    public let org: String
    /// Such as "Software Engineer, Agents".
    public let role: String
    public let `where`: String?
    public let stage: Stage
    /// The day it reached each stage it has reached.
    public let stages: [Stage: LocalTime]
    public let next: MotionNext?
    public let waitingOn: WaitingOn?
    public let rounds: [Round]
    public let facts: [Fact]
    public let url: URL?

    public init(
        org: String, role: String, where place: String? = nil, stage: Stage,
        stages: [Stage: LocalTime] = [:], next: MotionNext? = nil, waitingOn: WaitingOn? = nil,
        rounds: [Round] = [], facts: [Fact] = [], url: URL? = nil
    ) {
        self.org = org
        self.role = role
        self.where = place
        self.stage = stage
        self.stages = stages
        self.next = next
        self.waitingOn = waitingOn
        self.rounds = rounds
        self.facts = facts
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case org, role, `where`, stage, stages, next, rounds, facts, url
        case waitingOn = "waiting_on"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        org = try c.decode(String.self, forKey: .org)
        role = try c.decode(String.self, forKey: .role)
        self.where = try c.decodeIfPresent(String.self, forKey: .where)
        stage = try c.decode(Stage.self, forKey: .stage)
        let dated = (try? c.decodeIfPresent([String: String].self, forKey: .stages)) ?? [:]
        stages = Dictionary(
            uniqueKeysWithValues: (dated ?? [:]).compactMap { key, value in
                LocalTime(value).map { (Stage(rawValue: key), $0) }
            })
        next = (try? c.decodeIfPresent(MotionNext.self, forKey: .next)) ?? nil
        waitingOn = (try? c.decodeIfPresent(WaitingOn.self, forKey: .waitingOn)) ?? nil
        rounds = c.lenientList(Round.self, forKey: .rounds)
        facts = c.lenientList(Fact.self, forKey: .facts)
        url = (try? c.decodeIfPresent(URL.self, forKey: .url)) ?? nil
    }

    /// Where a role is: lead, talking, interviewing, offer, or ended.
    public struct Stage: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let lead = Stage(rawValue: "lead")
        public static let talking = Stage(rawValue: "talking")
        public static let interviewing = Stage(rawValue: "interviewing")
        public static let offer = Stage(rawValue: "offer")
        public static let ended = Stage(rawValue: "ended")
        public static let known = [lead, talking, interviewing, offer, ended]

        /// The four on the pipeline's line, in order.
        public static let pipeline = [lead, talking, interviewing, offer]
    }

    /// One round of the process, such as the recruiter call.
    public struct Round: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let title: String
        public let status: Status
        public let at: LocalTime?

        public init(id: String, title: String, status: Status, at: LocalTime? = nil) {
            self.id = id
            self.title = title
            self.status = status
            self.at = at
        }

        public struct Status: OpenValue {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let done = Status(rawValue: "done")
            public static let next = Status(rawValue: "next")
            public static let planned = Status(rawValue: "planned")
            public static let cancelled = Status(rawValue: "cancelled")
            public static let known = [done, next, planned, cancelled]
        }
    }

    /// A key fact, as a label and a value.
    public struct Fact: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let label: String
        public let value: String

        public init(id: String, label: String, value: String) {
            self.id = id
            self.label = label
            self.value = value
        }
    }
}

// MARK: - Body

/// A training block, as a coach keeps it: the plan, every week's sessions planned against done,
/// results towards a goal. Named so it never meets a SwiftUI view's `Body`.
public struct BodyBlock: Sendable, Equatable, Decodable {
    /// The shape of a week, such as "2 lifts and 2 easy runs a week".
    public let plan: String?
    /// The most time a week should take, in hours.
    public let hoursAWeek: Double?
    public let goal: Goal?
    /// Every week of the block, first to last.
    public let weeks: [Week]
    /// Timed efforts towards the goal, oldest first.
    public let results: [Training.Result]

    public init(
        plan: String? = nil, hoursAWeek: Double? = nil, goal: Goal? = nil, weeks: [Week] = [],
        results: [Training.Result] = []
    ) {
        self.plan = plan
        self.hoursAWeek = hoursAWeek
        self.goal = goal
        self.weeks = weeks
        self.results = results
    }

    enum CodingKeys: String, CodingKey {
        case plan, goal, weeks, results
        case hoursAWeek = "hours_a_week"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        hoursAWeek = try c.decodeIfPresent(Double.self, forKey: .hoursAWeek)
        goal = (try? c.decodeIfPresent(Goal.self, forKey: .goal)) ?? nil
        weeks = try c.decode([Week].self, forKey: .weeks)
        results = c.lenientList(Training.Result.self, forKey: .results)
    }

    public struct Goal: Sendable, Equatable, Decodable {
        public let title: String
        /// Such as "19:59".
        public let target: String?
        public let by: String?

        public init(title: String, target: String? = nil, by: String? = nil) {
            self.title = title
            self.target = target
            self.by = by
        }
    }

    public struct Week: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        /// Its first day.
        public let start: LocalTime
        public let focus: String?
        public let note: String?
        public let sessions: [Session]

        public init(
            id: String, start: LocalTime, focus: String? = nil, note: String? = nil,
            sessions: [Session] = []
        ) {
            self.id = id
            self.start = start
            self.focus = focus
            self.note = note
            self.sessions = sessions
        }

        enum CodingKeys: String, CodingKey { case id, start, focus, note, sessions }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            start = try c.decode(LocalTime.self, forKey: .start)
            focus = try c.decodeIfPresent(String.self, forKey: .focus)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            sessions = c.lenientList(Session.self, forKey: .sessions)
        }
    }

    /// One session: what's prescribed, what happened, and Kumo's notes on it, kept apart.
    public struct Session: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let date: LocalTime
        public let kind: Kind
        public let title: String
        /// The prescription in a line, such as "30 min easy · heart under 150".
        public let plan: String?
        public let planned: Planned?
        /// How Kumo wrote it; your tick, in the state, wins.
        public let done: Bool
        /// The day it was planned for before it moved.
        public let movedFrom: LocalTime?
        /// Dropped from the plan, not done.
        public let letGo: Bool
        public let result: SessionResult?
        /// Kumo's word on how it went.
        public let line: String?
        /// What it changes in the plan, such as "Next week's runs 35 → 40 min".
        public let changesNext: String?
        /// 0.18's prescription and detail together.
        public let detail: String?
        /// How it went, as you told Kumo, from 0.18.
        public let how: String?
        public let notes: [MotionNote]

        public init(
            id: String, date: LocalTime, kind: Kind, title: String, plan: String? = nil,
            planned: Planned? = nil, done: Bool = false, movedFrom: LocalTime? = nil,
            letGo: Bool = false, result: SessionResult? = nil, line: String? = nil,
            changesNext: String? = nil, detail: String? = nil, how: String? = nil,
            notes: [MotionNote] = []
        ) {
            self.id = id
            self.date = date
            self.kind = kind
            self.title = title
            self.plan = plan
            self.planned = planned
            self.done = done
            self.movedFrom = movedFrom
            self.letGo = letGo
            self.result = result
            self.line = line
            self.changesNext = changesNext
            self.detail = detail
            self.how = how
            self.notes = notes
        }

        enum CodingKeys: String, CodingKey {
            case id, date, kind, title, plan, planned, done, result, line, detail, how, notes
            case movedFrom = "moved_from"
            case letGo = "let_go"
            case changesNext = "changes_next"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            date = try c.decode(LocalTime.self, forKey: .date)
            kind = try c.decode(Kind.self, forKey: .kind)
            title = try c.decode(String.self, forKey: .title)
            plan = try c.decodeIfPresent(String.self, forKey: .plan)
            planned = (try? c.decodeIfPresent(Planned.self, forKey: .planned)) ?? nil
            done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
            movedFrom = (try? c.decodeIfPresent(LocalTime.self, forKey: .movedFrom)) ?? nil
            letGo = try c.decodeIfPresent(Bool.self, forKey: .letGo) ?? false
            result = (try? c.decodeIfPresent(SessionResult.self, forKey: .result)) ?? nil
            line = try c.decodeIfPresent(String.self, forKey: .line)
            changesNext = try c.decodeIfPresent(String.self, forKey: .changesNext)
            detail = try c.decodeIfPresent(String.self, forKey: .detail)
            how = try c.decodeIfPresent(String.self, forKey: .how)
            notes = c.lenientList(MotionNote.self, forKey: .notes)
        }

        /// What a session is, for its picture. 0.18's easy, intervals, tempo and long are runs, and
        /// strength a lift.
        public struct Kind: OpenValue {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let run = Kind(rawValue: "run")
            public static let lift = Kind(rawValue: "lift")
            public static let ride = Kind(rawValue: "ride")
            public static let swim = Kind(rawValue: "swim")
            public static let walk = Kind(rawValue: "walk")
            public static let climb = Kind(rawValue: "climb")
            public static let mobility = Kind(rawValue: "mobility")
            public static let sport = Kind(rawValue: "sport")
            public static let race = Kind(rawValue: "race")
            public static let rest = Kind(rawValue: "rest")
            public static let known = [
                run, lift, ride, swim, walk, climb, mobility, sport, race, rest,
                Kind(rawValue: "easy"), Kind(rawValue: "intervals"), Kind(rawValue: "tempo"),
                Kind(rawValue: "long"), Kind(rawValue: "strength"),
            ]

            /// The kind as one of today's, so 0.18's sessions draw the same.
            public var plain: Kind {
                switch rawValue {
                case "easy", "intervals", "tempo", "long": .run
                case "strength": .lift
                default: self
                }
            }
        }
    }

    /// What a session asks for, in numbers where it has them.
    public struct Planned: Sendable, Equatable, Decodable {
        public let minutes: Double?
        public let distanceKm: Double?
        /// A pace range per km, in seconds.
        public let pace: ClosedRange<Int>?
        public let heartUnder: Int?
        public let effort: String?

        public init(
            minutes: Double? = nil, distanceKm: Double? = nil, pace: ClosedRange<Int>? = nil,
            heartUnder: Int? = nil, effort: String? = nil
        ) {
            self.minutes = minutes
            self.distanceKm = distanceKm
            self.pace = pace
            self.heartUnder = heartUnder
            self.effort = effort
        }

        enum CodingKeys: String, CodingKey {
            case minutes, pace, effort
            case distanceKm = "distance_km"
            case heartUnder = "heart_under"
        }

        private struct Range: Decodable {
            let from: String
            let to: String
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            minutes = try c.decodeIfPresent(Double.self, forKey: .minutes)
            distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
            heartUnder = try c.decodeIfPresent(Int.self, forKey: .heartUnder)
            effort = try c.decodeIfPresent(String.self, forKey: .effort)
            if let range = (try? c.decodeIfPresent(Range.self, forKey: .pace)) ?? nil,
                let from = Pace.seconds(range.from), let to = Pace.seconds(range.to)
            {
                pace = min(from, to)...max(from, to)
            } else {
                pace = nil
            }
        }
    }

    /// What happened in a session: only what's known, from the Watch or from what you said.
    public struct SessionResult: Sendable, Equatable, Decodable {
        public let source: Source
        /// When it started, local, such as "07:12".
        public let at: String?
        public let minutes: Double?
        public let distanceKm: Double?
        /// Seconds per km.
        public let pace: Int?
        public let heartAvg: Int?
        public let heartMax: Int?
        /// Minutes in each heart-rate zone, by zone.
        public let zones: [Int: Double]
        /// Each km's pace, in seconds, in order.
        public let splits: [Int]
        public let felt: String?
        /// Out of 10.
        public let effort: Int?
        public let sets: [SetDone]

        public init(
            source: Source, at: String? = nil, minutes: Double? = nil, distanceKm: Double? = nil,
            pace: Int? = nil, heartAvg: Int? = nil, heartMax: Int? = nil,
            zones: [Int: Double] = [:],
            splits: [Int] = [], felt: String? = nil, effort: Int? = nil, sets: [SetDone] = []
        ) {
            self.source = source
            self.at = at
            self.minutes = minutes
            self.distanceKm = distanceKm
            self.pace = pace
            self.heartAvg = heartAvg
            self.heartMax = heartMax
            self.zones = zones
            self.splits = splits
            self.felt = felt
            self.effort = effort
            self.sets = sets
        }

        enum CodingKeys: String, CodingKey {
            case source, at, minutes, pace, zones, splits, felt, effort, sets
            case distanceKm = "distance_km"
            case heartAvg = "heart_avg"
            case heartMax = "heart_max"
        }

        private struct Zone: Decodable {
            let zone: Int
            let minutes: Double
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = (try? c.decode(Source.self, forKey: .source)) ?? .you
            at = try c.decodeIfPresent(String.self, forKey: .at)
            minutes = try c.decodeIfPresent(Double.self, forKey: .minutes)
            distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
            pace = ((try? c.decodeIfPresent(String.self, forKey: .pace)) ?? nil).flatMap(
                Pace.seconds)
            heartAvg = try c.decodeIfPresent(Int.self, forKey: .heartAvg)
            heartMax = try c.decodeIfPresent(Int.self, forKey: .heartMax)
            zones = Dictionary(
                c.lenientList(Zone.self, forKey: .zones).map { ($0.zone, $0.minutes) },
                uniquingKeysWith: +)
            splits =
                ((try? c.decodeIfPresent([String].self, forKey: .splits)) ?? nil)?
                .compactMap(Pace.seconds) ?? []
            felt = try c.decodeIfPresent(String.self, forKey: .felt)
            effort = try c.decodeIfPresent(Int.self, forKey: .effort)
            sets = c.lenientList(SetDone.self, forKey: .sets)
        }

        /// Where it came from: the Watch, or what you told Kumo.
        public struct Source: OpenValue {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let watch = Source(rawValue: "watch")
            public static let you = Source(rawValue: "you")
            public static let known = [watch, you]
        }
    }

    /// Sets of one exercise, as recorded.
    public struct SetDone: Sendable, Equatable, Decodable {
        public let exercise: String
        public let sets: Int?
        public let reps: Int?
        public let loadKg: Double?
        public let note: String?

        public init(
            exercise: String, sets: Int? = nil, reps: Int? = nil, loadKg: Double? = nil,
            note: String? = nil
        ) {
            self.exercise = exercise
            self.sets = sets
            self.reps = reps
            self.loadKg = loadKg
            self.note = note
        }

        enum CodingKeys: String, CodingKey {
            case exercise, sets, reps, note
            case loadKg = "load_kg"
        }
    }
}

/// Paces and times as minutes and seconds: "5:59" is 359 seconds.
public enum Pace {
    /// "5:59" or "20:12" as seconds; `nil` for anything else.
    public static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else {
            return nil
        }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    /// 359 as "5:59".
    public static func text(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = String(format: "%02d", seconds % 60)
        return hours > 0
            ? "\(hours):\(String(format: "%02d", minutes)):\(rest)" : "\(minutes):\(rest)"
    }
}

// MARK: - Project, learning and other

/// One part of a project, or a step of something being learnt.
public struct MotionPart: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let status: Status
    public let note: String?

    public init(id: String, title: String, status: Status, note: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.note = note
    }

    public struct Status: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let done = Status(rawValue: "done")
        public static let doing = Status(rawValue: "doing")
        public static let planned = Status(rawValue: "planned")
        public static let dropped = Status(rawValue: "dropped")
        public static let known = [done, doing, planned, dropped]
    }
}

/// Something being made, in parts.
public struct Project: Sendable, Equatable, Decodable {
    public let aim: String
    public let parts: [MotionPart]
    public let next: MotionNext?

    public init(aim: String, parts: [MotionPart] = [], next: MotionNext? = nil) {
        self.aim = aim
        self.parts = parts
        self.next = next
    }

    enum CodingKeys: String, CodingKey { case aim, parts, next }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aim = try c.decode(String.self, forKey: .aim)
        parts = c.lenientList(MotionPart.self, forKey: .parts)
        next = (try? c.decodeIfPresent(MotionNext.self, forKey: .next)) ?? nil
    }
}

/// Something being learnt, such as a language.
public struct Learning: Sendable, Equatable, Decodable {
    public let aim: String
    /// Such as "15 minutes a day".
    public let habit: String?
    public let steps: [MotionPart]
    /// Each stretch of practice, oldest first.
    public let log: [Entry]
    public let next: MotionNext?

    public init(
        aim: String, habit: String? = nil, steps: [MotionPart] = [], log: [Entry] = [],
        next: MotionNext? = nil
    ) {
        self.aim = aim
        self.habit = habit
        self.steps = steps
        self.log = log
        self.next = next
    }

    enum CodingKeys: String, CodingKey { case aim, habit, steps, log, next }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aim = try c.decode(String.self, forKey: .aim)
        habit = try c.decodeIfPresent(String.self, forKey: .habit)
        steps = c.lenientList(MotionPart.self, forKey: .steps)
        log = c.lenientList(Entry.self, forKey: .log)
        next = (try? c.decodeIfPresent(MotionNext.self, forKey: .next)) ?? nil
    }

    public struct Entry: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let date: LocalTime
        public let minutes: Double?
        public let text: String

        public init(id: String, date: LocalTime, minutes: Double? = nil, text: String) {
            self.id = id
            self.date = date
            self.minutes = minutes
            self.text = text
        }
    }
}

/// Something unfolding over weeks with no shape yet, such as a visa or a move.
public struct OtherMatter: Sendable, Equatable, Decodable {
    public let about: String
    public let status: String?
    public let waitingOn: WaitingOn?
    public let next: MotionNext?
    public let timeline: [CaseFile.Entry]
    public let todo: [Trip.Todo]

    public init(
        about: String, status: String? = nil, waitingOn: WaitingOn? = nil, next: MotionNext? = nil,
        timeline: [CaseFile.Entry] = [], todo: [Trip.Todo] = []
    ) {
        self.about = about
        self.status = status
        self.waitingOn = waitingOn
        self.next = next
        self.timeline = timeline
        self.todo = todo
    }

    enum CodingKeys: String, CodingKey {
        case about, status, next, timeline, todo
        case waitingOn = "waiting_on"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        about = try c.decode(String.self, forKey: .about)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        waitingOn = (try? c.decodeIfPresent(WaitingOn.self, forKey: .waitingOn)) ?? nil
        next = (try? c.decodeIfPresent(MotionNext.self, forKey: .next)) ?? nil
        timeline = c.lenientList(CaseFile.Entry.self, forKey: .timeline)
        todo = c.lenientList(Trip.Todo.self, forKey: .todo)
    }

    /// The list your ticks on its to-dos are under.
    public static let todoList = "todo"
}

extension KeyedDecodingContainer {
    /// A list, skipping any item it can't read, as from a newer server; `[]` when it's absent.
    func lenientList<Item: Decodable>(_ type: Item.Type, forKey key: Key) -> [Item] {
        ((try? decodeIfPresent([Lenient<Item>].self, forKey: key)) ?? nil)?.compactMap(\.item) ?? []
    }
}

/// An item that may not read, which never stops the list it's in from reading.
private struct Lenient<Item: Decodable>: Decodable {
    let item: Item?

    init(from decoder: any Decoder) throws {
        item = try? Item(from: decoder)
    }
}
