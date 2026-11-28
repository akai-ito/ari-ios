import Foundation

// Kumo's dream: once a day, at a time you set, Kumo looks back over the whole day, puts everything in
// order, and leaves a record of what it planned, tidied, noticed and saved for you. The Desk shows a
// moon from the dream until you've seen its record, then the sun.

/// A dream's id.
public struct DreamID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Where a line of a dream belongs. One Ari doesn't know shows under Noticed.
public struct DreamGroup: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Tomorrow put in order: Kumo's blocks and guesses, wake-ups set, moved or dropped.
    public static let planned = DreamGroup(rawValue: "planned")
    /// Memory tended: pages rewritten, merged, Now kept to what's live.
    public static let tidied = DreamGroup(rawValue: "tidied")
    /// What Kumo noticed or learnt.
    public static let noticed = DreamGroup(rawValue: "noticed")
    /// Kept for you: the day's journal, a message or a question for the morning.
    public static let saved = DreamGroup(rawValue: "saved")
    /// In the order the record shows them.
    public static let known = [planned, tidied, noticed, saved]

    /// The group to show it under: its own, or Noticed for one Ari doesn't know.
    public var shown: DreamGroup { isKnown ? self : .noticed }
}

/// How a dream started: at the dream time, or from Dream now. One Ari doesn't know counts as
/// scheduled.
public struct DreamTrigger: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let scheduled = DreamTrigger(rawValue: "scheduled")
    public static let manual = DreamTrigger(rawValue: "manual")
    public static let known = [scheduled, manual]
}

/// What kind of step a dream under way is taking. One Ari doesn't know shows as gathering.
public struct DreamStepGroup: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Reading back over the day.
    public static let gathering = DreamStepGroup(rawValue: "gathering")
    /// Tending memory.
    public static let tidying = DreamStepGroup(rawValue: "tidying")
    /// Tomorrow's blocks and wake-ups.
    public static let planning = DreamStepGroup(rawValue: "planning")
    /// Writing a day's journal entry.
    public static let journal = DreamStepGroup(rawValue: "journal")
    public static let known = [gathering, tidying, planning, journal]

    /// The group to show it as: its own, or gathering for one Ari doesn't know.
    public var shown: DreamStepGroup { isKnown ? self : .gathering }
}

/// One step of a dream under way, in a short line the server writes from what the dream is doing,
/// such as "Tidying Leo" or "Writing Monday's journal".
public struct DreamStep: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let group: DreamStepGroup
    public let text: String

    public init(at: Timestamp, group: DreamStepGroup, text: String) {
        self.at = at
        self.group = group
        self.text = text
    }
}

/// One short line of what a dream did, pointing at what it changed or is about.
public struct DreamLine: Sendable, Equatable, Decodable {
    public let group: DreamGroup
    /// Plain words, such as "Moved tomorrow's run to 07:30, before the 09:00 call".
    public let text: String
    /// The entry in Kumo's work for the change this line made, when it made one.
    public let done: DoneID?
    /// Whether undoing `done` can take the change back now.
    public let undo: Bool
    /// You took the change back.
    public let undone: Bool
    /// The memory page it changed or is about, such as `memory:journal/2026-11-26`.
    public let page: String?
    /// The wake-up it set, moved or dropped.
    public let wakeUp: WakeUpID?
    /// The item on Kumo's calendar it planned, moved or removed.
    public let event: CalendarItemID?
    /// A message it posted to you.
    public let message: MessageID?

    public init(
        group: DreamGroup, text: String, done: DoneID? = nil, undo: Bool = false,
        undone: Bool = false, page: String? = nil, wakeUp: WakeUpID? = nil,
        event: CalendarItemID? = nil, message: MessageID? = nil
    ) {
        self.group = group
        self.text = text
        self.done = done
        self.undo = undo
        self.undone = undone
        self.page = page
        self.wakeUp = wakeUp
        self.event = event
        self.message = message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decode(DreamGroup.self, forKey: .group)
        text = try container.decode(String.self, forKey: .text)
        done = try container.decodeIfPresent(DoneID.self, forKey: .done)
        undo = try container.decodeIfPresent(Bool.self, forKey: .undo) ?? false
        undone = try container.decodeIfPresent(Bool.self, forKey: .undone) ?? false
        page = try container.decodeIfPresent(String.self, forKey: .page)
        wakeUp = try container.decodeIfPresent(WakeUpID.self, forKey: .wakeUp)
        event = try container.decodeIfPresent(CalendarItemID.self, forKey: .event)
        message = try container.decodeIfPresent(MessageID.self, forKey: .message)
    }

    enum CodingKeys: String, CodingKey {
        case group, text, done, undo, undone, page, event, message
        case wakeUp = "wake_up"
    }
}

/// One of Kumo's dreams: what it looked back on, when it ran, and its record. It's new until you've
/// seen it.
public struct Dream: Sendable, Equatable, Decodable, Identifiable {
    public let id: DreamID
    /// The local day it mostly looked back on, such as `2026-11-26` for a dream at 04:00 on the 27th.
    public let day: String
    public let trigger: DreamTrigger
    public let startedAt: Timestamp
    public let endedAt: Timestamp
    /// The night in a line, in Kumo's words.
    public let headline: String?
    /// In the order Kumo wrote them.
    public let lines: [DreamLine]
    /// When you saw it; until then it's new.
    public let seenAt: Timestamp?

    public init(
        id: DreamID, day: String, trigger: DreamTrigger = .scheduled, startedAt: Timestamp,
        endedAt: Timestamp, headline: String? = nil, lines: [DreamLine] = [],
        seenAt: Timestamp? = nil
    ) {
        self.id = id
        self.day = day
        self.trigger = trigger
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.headline = headline
        self.lines = lines
        self.seenAt = seenAt
    }

    /// Whether you haven't seen it yet: the Desk shows a moon for it.
    public var isNew: Bool { seenAt == nil }

    /// Its lines in the record's groups, in the record's order, leaving out groups with none.
    public var groups: [(group: DreamGroup, lines: [DreamLine])] {
        DreamGroup.known.compactMap { group in
            let lines = lines.filter { $0.group.shown == group }
            return lines.isEmpty ? nil : (group, lines)
        }
    }

    /// The dream as it is now that you've seen it.
    public func seen(at time: Timestamp) -> Dream {
        Dream(
            id: id, day: day, trigger: trigger, startedAt: startedAt, endedAt: endedAt,
            headline: headline, lines: lines, seenAt: seenAt ?? time)
    }

    /// The dream with a line's change taken back, as the record will say once asked again.
    public func undoing(_ entry: DoneID) -> Dream {
        Dream(
            id: id, day: day, trigger: trigger, startedAt: startedAt, endedAt: endedAt,
            headline: headline,
            lines: lines.map { line in
                guard line.done == entry else { return line }
                return DreamLine(
                    group: line.group, text: line.text, done: line.done, undo: false,
                    undone: true, page: line.page, wakeUp: line.wakeUp, event: line.event,
                    message: line.message)
            }, seenAt: seenAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, day, trigger, headline, lines
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case seenAt = "seen_at"
    }
}

/// Kumo's dream as it stands: when it dreams each night, when the next one is, one under way, and
/// the latest record. The answer to `GET /v0/dream`, Dream now and setting the time.
public struct DreamState: Sendable, Equatable, Decodable {
    /// When Kumo dreams each night, on your local clock, such as `04:00`.
    public let time: String
    /// When the next dream is due.
    public let nextAt: Timestamp
    /// A dream under way, while there is one.
    public let dreaming: Dreaming?
    /// The latest dream, once there's been one.
    public let latest: Dream?

    public init(time: String, nextAt: Timestamp, dreaming: Dreaming? = nil, latest: Dream? = nil) {
        self.time = time
        self.nextAt = nextAt
        self.dreaming = dreaming
        self.latest = latest
    }

    /// A dream under way: since when, what started it, and its latest steps.
    public struct Dreaming: Sendable, Equatable, Decodable {
        public let since: Timestamp
        public let trigger: DreamTrigger
        /// Oldest first: up to the server's latest 20 when read, then each `dream.progress` after.
        public let steps: [DreamStep]

        public init(since: Timestamp, trigger: DreamTrigger, steps: [DreamStep] = []) {
            self.since = since
            self.trigger = trigger
            self.steps = steps
        }

        /// The same, a step further on. It keeps the latest 40.
        public func adding(_ step: DreamStep) -> Dreaming {
            Dreaming(since: since, trigger: trigger, steps: Array((steps + [step]).suffix(40)))
        }

        enum CodingKeys: String, CodingKey {
            case since, trigger, steps
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            since = try c.decode(Timestamp.self, forKey: .since)
            trigger = try c.decode(DreamTrigger.self, forKey: .trigger)
            // A server from before the dream's progress has no steps.
            steps = try c.decodeIfPresent([DreamStep].self, forKey: .steps) ?? []
        }
    }

    /// The same, with these changes.
    public func with(dreaming: Dreaming?? = nil, latest: Dream?? = nil) -> DreamState {
        DreamState(
            time: time, nextAt: nextAt, dreaming: dreaming ?? self.dreaming,
            latest: latest ?? self.latest)
    }

    enum CodingKeys: String, CodingKey {
        case time, dreaming, latest
        case nextAt = "next_at"
    }
}

/// The body of `PUT /v0/dream/time`: such as `04:00`, on your local clock.
public struct DreamTime: Sendable, Equatable, Codable {
    public let time: String

    public init(time: String) { self.time = time }
}

/// The answer to `POST /v0/dreams/{dream}/seen`.
public struct DreamResult: Sendable, Equatable, Decodable {
    public let dream: Dream
}

/// `dream.progress`: while Kumo dreams, it started a step. It never notifies.
public struct DreamProgress: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let step: DreamStep
}

/// `dream.finished`: Kumo finished a dream and left its record. It never notifies.
public struct DreamFinished: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let dream: Dream
}
