import Foundation

// The general shapes of a matter beyond a trip and a training block: a Pursuit, an Occasion and a
// Case. Nothing in them is built for one person: a job search is a Pursuit, and so is a flat hunt or
// a hire. Kumo writes all of it; the only thing you tap is an occasion's prep, whose ticks are in the
// thing's state.

/// Who a matter is waiting on, and since when, such as "them" since 15 October.
public struct WaitingOn: Sendable, Equatable, Decodable {
    /// Such as "Poppy", "them" or "the landlord".
    public let who: String
    public let since: Timestamp

    public init(who: String, since: Timestamp) {
        self.who = who
        self.since = since
    }
}

/// What happens next, and when if it's set, such as "Second round" on Tuesday 17 November.
public struct NextStep: Sendable, Equatable, Decodable {
    public let text: String
    public let at: Timestamp?

    public init(text: String, at: Timestamp? = nil) {
        self.text = text
        self.at = at
    }
}

/// One outcome, with several options moving through stages: a job search, a flat hunt, YC, a hire.
/// It opens with what you're after and how you play it, which Kumo writes from what you say.
public struct Pursuit: Sendable, Equatable, Decodable {
    /// What you're after, such as "AI engineering or C++ HFT systems, at quant firms, in London or
    /// Amsterdam."
    public let after: String
    /// How you play it: Kumo's standing rules for this pursuit, one line each.
    public let play: [String]
    /// The options in play, in Kumo's order.
    public let options: [Option]

    public init(after: String, play: [String] = [], options: [Option] = []) {
        self.after = after
        self.play = play
        self.options = options
    }

    enum CodingKeys: String, CodingKey { case after, play, options }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        after = try c.decode(String.self, forKey: .after)
        play = try c.decodeIfPresent([String].self, forKey: .play) ?? []
        options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
    }

    /// One option: a role at a firm, a flat, a candidate.
    public struct Option: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        /// What you'd call it at a glance: the firm for a job ("QRT"), the flat for a flat hunt, the
        /// person for a hire.
        public let name: String
        /// The organisation behind it when that isn't the name, such as the agency for a flat.
        public let org: String?
        /// The role, for a job or a hire, such as "Senior AI Engineer". Not in the draft contract:
        /// the approved design shows it beside the firm.
        public let role: String?
        /// Where it stands, such as "Interviews".
        public let stage: String
        /// Every stage this option goes through, in order, such as "Screened", "Interviews",
        /// "Awaiting answer", "Offer"; `[]` when Kumo hasn't set them out.
        public let stages: [String]
        public let people: [Person]
        public let next: NextStep?
        public let waitingOn: WaitingOn?
        /// Kumo's line on it, such as "Technical done today".
        public let note: String?

        public init(
            id: String, name: String, org: String? = nil, role: String? = nil, stage: String,
            stages: [String] = [], people: [Person] = [], next: NextStep? = nil,
            waitingOn: WaitingOn? = nil,
            note: String? = nil
        ) {
            self.id = id
            self.name = name
            self.org = org
            self.role = role
            self.stage = stage
            self.stages = stages
            self.people = people
            self.next = next
            self.waitingOn = waitingOn
            self.note = note
        }

        enum CodingKeys: String, CodingKey {
            case id, name, org, role, stage, stages, people, next, note
            case waitingOn = "waiting_on"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            org = try c.decodeIfPresent(String.self, forKey: .org)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            stage = try c.decode(String.self, forKey: .stage)
            stages = try c.decodeIfPresent([String].self, forKey: .stages) ?? []
            people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
            next = try c.decodeIfPresent(NextStep.self, forKey: .next)
            waitingOn = try c.decodeIfPresent(WaitingOn.self, forKey: .waitingOn)
            note = try c.decodeIfPresent(String.self, forKey: .note)
        }
    }

    /// Someone on an option, such as the recruiter.
    public struct Person: Sendable, Equatable, Decodable {
        public let name: String
        /// Such as "Recruiter" or "Hiring manager".
        public let role: String
        /// Their page in Kumo's memory.
        public let page: PageAddress?

        public init(name: String, role: String, page: PageAddress? = nil) {
            self.name = name
            self.role = role
            self.page = page
        }
    }
}

/// A dated event with people and prep: an appointment, a birthday, a dinner, a wedding.
public struct Occasion: Sendable, Equatable, Decodable {
    public let start: Timestamp
    public let end: Timestamp?
    /// Whether it takes whole days, such as a birthday, so no time shows. Its days are read in the
    /// device's calendar from `start` and `end`.
    public let allDay: Bool
    /// Where it is, such as "Bright Smile Dental, 14 Upper Street". It's `where` on the wire, which
    /// is a Swift keyword.
    public let place: String?
    /// Who else is there.
    public let people: [Person]
    /// What to do before it, which you tick.
    public let prep: [Prep]
    /// Whether Kumo will check in after it.
    public let checkIn: Bool

    public init(
        start: Timestamp, end: Timestamp? = nil, allDay: Bool = false, place: String? = nil,
        people: [Person] = [], prep: [Prep] = [], checkIn: Bool = false
    ) {
        self.start = start
        self.end = end
        self.allDay = allDay
        self.place = place
        self.people = people
        self.prep = prep
        self.checkIn = checkIn
    }

    enum CodingKeys: String, CodingKey {
        case start, end, people, prep
        case allDay = "all_day"
        case place = "where"
        case checkIn = "check_in"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Timestamp.self, forKey: .start)
        end = try c.decodeIfPresent(Timestamp.self, forKey: .end)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        place = try c.decodeIfPresent(String.self, forKey: .place)
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
        prep = try c.decodeIfPresent([Prep].self, forKey: .prep) ?? []
        checkIn = try c.decodeIfPresent(Bool.self, forKey: .checkIn) ?? false
    }

    public struct Person: Sendable, Equatable, Decodable {
        /// Such as "Dr Shah".
        public let name: String
        /// Their page in Kumo's memory.
        public let page: PageAddress?

        public init(name: String, page: PageAddress? = nil) {
            self.name = name
            self.page = page
        }
    }

    /// Something to do before it. `done` is how Kumo wrote it; your tick, in the state, wins.
    public struct Prep: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let text: String
        public let done: Bool

        public init(id: String, text: String, done: Bool = false) {
            self.id = id
            self.text = text
            self.done = done
        }

        enum CodingKeys: String, CodingKey { case id, text, done }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        }
    }
}

/// A problem with back-and-forth: the boiler, a refund, a visa. On the wire its kind is `case`.
public struct CaseFile: Sendable, Equatable, Decodable {
    /// What's wrong, such as "The boiler cuts out after ten minutes, so no hot water."
    public let problem: String
    /// Where it stands, in a few words, such as "Reported to the landlord".
    public let status: String
    public let waitingOn: WaitingOn?
    /// What's happened, as Kumo wrote it down.
    public let timeline: [Entry]
    public let next: NextStep?

    public init(
        problem: String, status: String, waitingOn: WaitingOn? = nil, timeline: [Entry] = [],
        next: NextStep? = nil
    ) {
        self.problem = problem
        self.status = status
        self.waitingOn = waitingOn
        self.timeline = timeline
        self.next = next
    }

    enum CodingKeys: String, CodingKey {
        case problem, status, timeline, next
        case waitingOn = "waiting_on"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        problem = try c.decode(String.self, forKey: .problem)
        status = try c.decode(String.self, forKey: .status)
        waitingOn = try c.decodeIfPresent(WaitingOn.self, forKey: .waitingOn)
        timeline = try c.decodeIfPresent([Entry].self, forKey: .timeline) ?? []
        next = try c.decodeIfPresent(NextStep.self, forKey: .next)
    }

    /// One thing that happened, such as "Emailed the landlord with the error code".
    public struct Entry: Sendable, Equatable, Decodable {
        public let at: Timestamp
        public let text: String

        public init(at: Timestamp, text: String) {
            self.at = at
            self.text = text
        }
    }
}
