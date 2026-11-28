import Foundation

// Kumo's plans: the times it will wake up and look at something for you. Kumo sets them, keeps them
// current as your life moves, and you can move, change or cancel any of them.

/// A wake-up's id.
public struct WakeUpID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A time Kumo will wake up and look at something for you: a follow-up, a look after an event, a
/// standing job, or something you asked for. When it comes due, Kumo looks first, then messages you
/// if that's useful, moves it if things changed, or drops it if it's moot, and Done says which.
public struct WakeUp: Sendable, Equatable, Decodable, Identifiable {
    public let id: WakeUpID
    /// When it's next due, a concrete time Kumo worked out, such as the end of the event it's for.
    public let at: Timestamp
    /// What it is in a few plain words, as you'd say it, such as "Ask how the technical went": the
    /// line Kumo's plans show. A server from before titles leaves it out; ``shownTitle`` falls back.
    public let title: String?
    /// What Kumo will do when it wakes, in its own words, shown with `why` when a plan is open.
    public let what: String
    /// Why, in Kumo's words: what it will have in mind when it wakes.
    public let why: String
    /// How it comes back; `nil` for a one-off.
    public let `repeat`: Repeat?
    /// Who made it.
    public let by: WakeUpAuthor
    /// Where it came from.
    public let source: WakeUpSource
    /// The thing in motion it's about.
    public let motion: MotionID?
    /// When it was set.
    public let setAt: Timestamp

    public init(
        id: WakeUpID, at: Timestamp, title: String? = nil, what: String, why: String,
        repeat: Repeat? = nil, by: WakeUpAuthor = .kumo, source: WakeUpSource,
        motion: MotionID? = nil, setAt: Timestamp
    ) {
        self.id = id
        self.at = at
        self.title = title
        self.what = what
        self.why = why
        self.repeat = `repeat`
        self.by = by
        self.source = source
        self.motion = motion
        self.setAt = setAt
    }

    /// Its line in Kumo's plans: its title, or what it's for from a server before titles.
    public var shownTitle: String { title ?? what }

    enum CodingKeys: String, CodingKey {
        case id, at, title, what, why, `repeat`, by, source, motion
        case setAt = "set_at"
    }
}

/// Who made a wake-up: you asked for it, or Kumo set it itself. One Ari doesn't know counts as
/// Kumo's.
public struct WakeUpAuthor: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let you = WakeUpAuthor(rawValue: "you")
    public static let kumo = WakeUpAuthor(rawValue: "kumo")
    public static let known = [you, kumo]
}

/// A day of the week, in your time zone.
public struct Weekday: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let monday = Weekday(rawValue: "mon")
    public static let tuesday = Weekday(rawValue: "tue")
    public static let wednesday = Weekday(rawValue: "wed")
    public static let thursday = Weekday(rawValue: "thu")
    public static let friday = Weekday(rawValue: "fri")
    public static let saturday = Weekday(rawValue: "sat")
    public static let sunday = Weekday(rawValue: "sun")
    /// Monday first, as the protocol counts them.
    public static let known = [monday, tuesday, wednesday, thursday, friday, saturday, sunday]
    public static let weekdays = [monday, tuesday, wednesday, thursday, friday]
    public static let weekend = [saturday, sunday]
}

/// A wake-up that comes back: on these days, at this time in your time zone, wherever you are, such
/// as weekdays at 09:00, until it's stopped or, when it has an end, a number of times or up to a day.
public struct Repeat: Sendable, Equatable, Codable {
    public let days: [Weekday]
    /// Such as `09:00`.
    public let time: String
    /// How many more times it comes round, counting the next; it ends after the last. `nil` when
    /// it repeats until stopped.
    public let left: Int?
    /// The last day it comes round, on your local clock, such as `2026-12-22`; it ends after that.
    public let until: String?

    public init(days: [Weekday], time: String, left: Int? = nil, until: String? = nil) {
        self.days = days
        self.time = time
        self.left = left
        self.until = until
    }

    /// The last day it comes round, at its start on `calendar`, when it has one.
    public func lastDay(in calendar: Calendar = .current) -> Date? {
        until.flatMap(LocalTime.init).map { $0.date(in: calendar) }
    }

    /// Whether it comes back every day of the week.
    public var isDaily: Bool { Set(days) == Set(Weekday.known) }
}

/// Where a wake-up came from: your chat with Kumo, a mail Kumo read, a calendar event, or another
/// wake-up. A kind Ari doesn't know shows by its title.
public struct WakeUpSource: Sendable, Equatable, Decodable {
    public let kind: Kind
    /// A line naming it, such as "Tess Harlow: Thursday's technical".
    public let title: String
    /// A mail: to open in Mail with `message://` and its Message-ID.
    public let mail: Mail?
    /// A calendar event: to open by its uid.
    public let event: Event?

    public init(kind: Kind, title: String, mail: Mail? = nil, event: Event? = nil) {
        self.kind = kind
        self.title = title
        self.mail = mail
        self.event = event
    }

    public struct Kind: OpenValue {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let chat = Kind(rawValue: "chat")
        public static let mail = Kind(rawValue: "mail")
        public static let calendar = Kind(rawValue: "calendar")
        public static let wakeUp = Kind(rawValue: "wake_up")
        public static let known = [chat, mail, calendar, wakeUp]
    }

    public struct Mail: Sendable, Equatable, Decodable {
        public let account: String?
        /// Without angle brackets.
        public let messageID: String

        public init(account: String? = nil, messageID: String) {
            self.account = account
            self.messageID = messageID
        }

        enum CodingKeys: String, CodingKey {
            case account
            case messageID = "message_id"
        }
    }

    public struct Event: Sendable, Equatable, Decodable {
        public let uid: String

        public init(uid: String) { self.uid = uid }
    }
}

/// The body of `PATCH /v0/wakeups/{wake_up}`: what to change, leaving out what stays.
public struct WakeUpChange: Sendable, Equatable, Encodable {
    /// When it's next due; for a repeating one, only this time.
    public var at: Timestamp?
    /// How it comes back: a new repeat, `.some(nil)` to make it a one-off, or `nil` to keep it.
    public var `repeat`: Repeat??
    /// Its title in Kumo's plans.
    public var title: String?
    public var what: String?
    public var why: String?

    public init(
        at: Timestamp? = nil, repeat: Repeat?? = nil, title: String? = nil, what: String? = nil,
        why: String? = nil
    ) {
        self.at = at
        self.repeat = `repeat`
        self.title = title
        self.what = what
        self.why = why
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(at, forKey: .at)
        switch `repeat` {
        case .some(.some(let value)): try container.encode(value, forKey: .repeat)
        case .some(.none): try container.encodeNil(forKey: .repeat)
        case .none: break
        }
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(what, forKey: .what)
        try container.encodeIfPresent(why, forKey: .why)
    }

    enum CodingKeys: String, CodingKey {
        case at, `repeat`, title, what, why
    }
}

/// The answer to `GET /v0/wakeups`: soonest first.
public struct WakeUpList: Sendable, Equatable, Decodable {
    public let wakeUps: [WakeUp]

    enum CodingKeys: String, CodingKey {
        case wakeUps = "wake_ups"
    }
}

/// The answer to `PATCH /v0/wakeups/{wake_up}`: the wake-up as it is now.
/// The answer to `POST /v0/wakeups/{wake_up}/skip`: the wake-up at its next time, or `nil` when
/// the time skipped was its last and it's gone.
public struct WakeUpSkipped: Sendable, Equatable, Decodable {
    public let wakeUp: WakeUp?

    enum CodingKeys: String, CodingKey {
        case wakeUp = "wake_up"
    }
}

public struct WakeUpResult: Sendable, Equatable, Decodable {
    public let wakeUp: WakeUp

    enum CodingKeys: String, CodingKey {
        case wakeUp = "wake_up"
    }
}
