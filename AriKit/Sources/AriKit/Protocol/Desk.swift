import Foundation

// Kumo's Desk: where Ito opens. It rolls and never resets: the morning card, what's coming up and
// what's waiting on you.

/// Everything on the Desk at once. It's small, so `desk.changed` carries all of it.
public struct Desk: Sendable, Equatable, Decodable {
    /// The morning card, or "since this morning", while it's current.
    public let briefing: Briefing?
    /// The next day and a half, and anything big this week, in time order.
    public let comingUp: [CalendarItem]
    /// Drafts, invites, times to check and questions, oldest first, until each is done.
    public let waiting: [DeskCard]

    public init(
        briefing: Briefing? = nil, comingUp: [CalendarItem] = [], waiting: [DeskCard] = []
    ) {
        self.briefing = briefing
        self.comingUp = comingUp
        self.waiting = waiting
    }

    enum CodingKeys: String, CodingKey {
        case briefing, waiting
        case comingUp = "coming_up"
    }
}

/// A briefing's id.
public struct BriefingID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// What Kumo tells you at the first calm moment of the morning, or later "since this morning". The
/// box drops it at 14:00, or when a newer one replaces it.
public struct Briefing: Sendable, Equatable, Decodable, Identifiable {
    public let id: BriefingID
    public let kind: BriefingKind
    public let at: Timestamp
    /// Kumo's lines, most important first, each perhaps opening a card.
    public let lines: [BriefingLine]
    /// How many small things Kumo handled that the lines don't mention, for "Also handled 9 small
    /// things".
    public let handled: Int
    /// When an app first showed it.
    public let readAt: Timestamp?

    public init(
        id: BriefingID, kind: BriefingKind = .morning, at: Timestamp, lines: [BriefingLine],
        handled: Int = 0, readAt: Timestamp? = nil
    ) {
        self.id = id
        self.kind = kind
        self.at = at
        self.lines = lines
        self.handled = handled
        self.readAt = readAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, at, lines, handled
        case readAt = "read_at"
    }
}

public struct BriefingKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let morning = BriefingKind(rawValue: "morning")
    /// "Since this morning": only when something new happened after you read the morning one.
    public static let since = BriefingKind(rawValue: "since")
    public static let known = [morning, since]
}

public struct BriefingLine: Sendable, Equatable, Decodable {
    /// One line, plain words.
    public let text: String
    /// The card waiting on you that it's about.
    public let card: CardID?

    public init(text: String, card: CardID? = nil) {
        self.text = text
        self.card = card
    }
}

/// A card's id.
public struct CardID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Something waiting on you. Its kind's payload sits under a field of the same name. A kind Ari
/// doesn't know shows its title and options.
public struct DeskCard: Sendable, Equatable, Decodable, Identifiable {
    public let id: CardID
    public let kind: CardKind
    /// The thing in motion it's about, such as the job search.
    public let motion: MotionID?
    /// When it began waiting, for "since Wed".
    public let at: Timestamp
    /// One line, such as "Draft to Poppy".
    public let title: String
    /// The buttons to draw, in order. Answering with one sends its label.
    public let options: [Ask.Option]
    /// Whether words work as an answer too; for a draft, they ask for a change.
    public let allowsText: Bool
    /// `working` while the box acts on your answer, such as rewriting a draft.
    public let state: CardState?
    public let draft: DraftCard?
    public let invite: InviteCard?
    public let times: TimesCard?
    public let question: QuestionCard?
    public let offer: OfferCard?

    public init(
        id: CardID, kind: CardKind, motion: MotionID? = nil, at: Timestamp,
        title: String, options: [Ask.Option] = [], allowsText: Bool = false,
        state: CardState? = nil, draft: DraftCard? = nil, invite: InviteCard? = nil,
        times: TimesCard? = nil, question: QuestionCard? = nil, offer: OfferCard? = nil
    ) {
        self.id = id
        self.kind = kind
        self.motion = motion
        self.at = at
        self.title = title
        self.options = options
        self.allowsText = allowsText
        self.state = state
        self.draft = draft
        self.invite = invite
        self.times = times
        self.question = question
        self.offer = offer
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, motion, at, title, options, state, draft, invite, times, question, offer
        case allowsText = "allows_text"
    }
}

/// Whether the box is acting on your answer. A state Ari doesn't know draws as idle.
public struct CardState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let working = CardState(rawValue: "working")
    public static let known = [working]
}

public struct CardKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A mail Kumo wrote for you, in your Drafts folder. You send it from Mail.
    public static let draft = CardKind(rawValue: "draft")
    /// A calendar invitation, held in Kumo's calendar until you answer.
    public static let invite = CardKind(rawValue: "invite")
    /// Free times to check against what Kumo can't see, such as your work calendar.
    public static let times = CardKind(rawValue: "times")
    /// A question: Kumo wasn't sure, or wants a small decision.
    public static let question = CardKind(rawValue: "question")
    /// A capability Kumo offers to switch on. You always confirm.
    public static let offer = CardKind(rawValue: "offer")
    public static let known = [draft, invite, times, question, offer]
}

/// A reply Kumo wrote into your Drafts folder. Kumo never sends it: you open it in Mail and send it
/// yourself.
public struct DraftCard: Sendable, Equatable, Decodable {
    /// The mail account it's in, such as `icloud` or `outlook`.
    public let account: String
    public let from: String
    public let to: [String]
    public let cc: [String]?
    public let subject: String
    /// Plain text, as it will be sent.
    public let body: String
    /// The draft's own Message-ID, without angle brackets, for opening it in Mail.
    public let messageID: String
    /// The Message-ID of the mail it answers.
    public let inReplyTo: String?

    public init(
        account: String, from: String, to: [String], cc: [String]? = nil, subject: String,
        body: String, messageID: String, inReplyTo: String? = nil
    ) {
        self.account = account
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.messageID = messageID
        self.inReplyTo = inReplyTo
    }

    enum CodingKeys: String, CodingKey {
        case account, from, to, cc, subject, body
        case messageID = "message_id"
        case inReplyTo = "in_reply_to"
    }
}

/// An invitation, held on Kumo's calendar until you answer; your answer goes back through iCloud.
public struct InviteCard: Sendable, Equatable, Decodable {
    public let event: CalendarItem
    /// Something already at that time.
    public let clash: CalendarItem?

    public init(event: CalendarItem, clash: CalendarItem? = nil) {
        self.event = event
        self.clash = clash
    }
}

/// Times to check against your work calendar, which Kumo can't see. You answer with the ones that
/// are clear.
public struct TimesCard: Sendable, Equatable, Decodable {
    /// What the times are for, such as "A call with Poppy".
    public let purpose: String
    public let slots: [TimeSlot]

    public init(purpose: String, slots: [TimeSlot]) {
        self.purpose = purpose
        self.slots = slots
    }
}

/// A time Kumo offers. Answering names it by its place in the card's slots.
public struct TimeSlot: Sendable, Equatable, Decodable {
    public let start: Timestamp
    public let end: Timestamp
    /// Such as "WFH day".
    public let note: String?

    public init(start: Timestamp, end: Timestamp, note: String? = nil) {
        self.start = start
        self.end = end
        self.note = note
    }
}

/// Something Kumo isn't sure about, such as whether a mail it binned was right. Its buttons are the
/// card's options.
public struct QuestionCard: Sendable, Equatable, Decodable {
    public let text: String

    public init(text: String) { self.text = text }
}

/// A capability Kumo offers to switch on, for a need that keeps coming up.
public struct OfferCard: Sendable, Equatable, Decodable {
    /// What Kumo offers, in its words.
    public let text: String
    /// The capability it would switch on.
    public let capability: CapabilityID?

    public init(text: String, capability: CapabilityID? = nil) {
        self.text = text
        self.capability = capability
    }
}

/// Your answer to a card: exactly one of an option's label, the slots that are clear (by their
/// place in the card), or words (for a draft, a change such as "a bit more casual").
public struct CardAnswer: Sendable, Equatable, Codable {
    public let option: String?
    public let slots: [Int]?
    public let text: String?

    /// You tapped one of the card's options.
    public init(option: String) {
        self.init(option: option, slots: nil, text: nil)
    }

    /// You ticked the times that are clear, by their place in the card.
    public init(slots: [Int]) {
        self.init(option: nil, slots: slots, text: nil)
    }

    /// You wrote an answer.
    public init(text: String) {
        self.init(option: nil, slots: nil, text: text)
    }

    private init(option: String?, slots: [Int]?, text: String?) {
        self.option = option
        self.slots = slots
        self.text = text
    }
}

/// A calendar event's id, from the box.
public struct CalendarItemID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// An event on one of your calendars, as the box reads it from iCloud. The phone opens it in Apple's
/// own views, by its `uid`.
public struct CalendarItem: Sendable, Equatable, Decodable, Identifiable {
    public let id: CalendarItemID
    /// The iCalendar UID, for finding the same event on the phone.
    public let uid: String
    public let title: String
    public let start: When
    public let end: When
    public let allDay: Bool
    public let location: String?
    public let calendar: CalendarName
    /// When to leave, if Kumo worked out travel.
    public let leaveAt: Timestamp?
    /// The thing in motion it belongs to, such as the Florence trip.
    public let motion: MotionID?
    public let status: CalendarStatus?

    public init(
        id: CalendarItemID, uid: String, title: String, start: When, end: When,
        allDay: Bool = false, location: String? = nil, calendar: CalendarName,
        leaveAt: Timestamp? = nil, motion: MotionID? = nil, status: CalendarStatus? = nil
    ) {
        self.id = id
        self.uid = uid
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.calendar = calendar
        self.leaveAt = leaveAt
        self.motion = motion
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, uid, title, start, end, location, calendar, motion, status
        case allDay = "all_day"
        case leaveAt = "leave_at"
    }
}

public struct CalendarName: Sendable, Equatable, Decodable {
    public let name: String
    /// Kumo's own calendar, of holds, travel and prep.
    public let kumo: Bool

    public init(name: String, kumo: Bool = false) {
        self.name = name
        self.kumo = kumo
    }
}

public struct CalendarStatus: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A time Kumo is keeping free, such as one it offered a recruiter.
    public static let hold = CalendarStatus(rawValue: "hold")
    public static let tentative = CalendarStatus(rawValue: "tentative")
    public static let confirmed = CalendarStatus(rawValue: "confirmed")
    public static let known = [hold, tentative, confirmed]
}

/// The body of `POST /v0/calendar/events`: an event for your own calendar, which the box writes.
public struct NewCalendarEvent: Sendable, Equatable, Codable {
    public let title: String
    /// An instant, or for an all-day event its first day.
    public let start: When
    public let end: When
    public let location: String?
    public let notes: String?

    public init(
        title: String, start: When, end: When, location: String? = nil, notes: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
    }
}

/// A Done entry's id.
public struct DoneID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One thing Kumo did without you. A message replying to it, with its id as `done`,
/// corrects it, and the correction becomes a preference.
public struct DoneEntry: Sendable, Equatable, Decodable, Identifiable {
    public let id: DoneID
    public let at: Timestamp
    /// Such as "Unsubscribed from Deliveroo promos and binned 3".
    public let text: String
    /// Why, in a line.
    public let reason: String?
    /// The mail it was about.
    public let mail: DoneMail?
    /// The event it added or changed.
    public let event: CalendarItem?
    public let motion: MotionID?
    /// Whether it can be undone.
    public let undo: Bool
    /// A mail Kumo read and left alone, "read, nothing needed": folded into one line a day.
    public let quiet: Bool

    public init(
        id: DoneID, at: Timestamp, text: String, reason: String? = nil, mail: DoneMail? = nil,
        event: CalendarItem? = nil, motion: MotionID? = nil, undo: Bool = false,
        quiet: Bool = false
    ) {
        self.id = id
        self.at = at
        self.text = text
        self.reason = reason
        self.mail = mail
        self.event = event
        self.motion = motion
        self.undo = undo
        self.quiet = quiet
    }
}

/// The mail a Done entry was about, for opening it in Mail.
public struct DoneMail: Sendable, Equatable, Decodable {
    public let account: String?
    /// Without angle brackets.
    public let messageID: String
    public let from: String
    public let subject: String

    public init(account: String? = nil, messageID: String, from: String, subject: String) {
        self.account = account
        self.messageID = messageID
        self.from = from
        self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
        case account, from, subject
        case messageID = "message_id"
    }
}

/// A page of Done, newest first.
public struct DonePage: Sendable, Equatable, Decodable {
    public let entries: [DoneEntry]
    public let hasMore: Bool

    public init(entries: [DoneEntry], hasMore: Bool = false) {
        self.entries = entries
        self.hasMore = hasMore
    }

    enum CodingKeys: String, CodingKey {
        case entries
        case hasMore = "has_more"
    }
}

/// The answer to `POST /v0/done/{entry}/undo`: the entry, marked undone in its text.
public struct DoneResult: Sendable, Equatable, Decodable {
    public let entry: DoneEntry
}

/// A scheduled look's id.
public struct JobID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A look Kumo scheduled for itself: a follow-up, a check-in after an event, or a
/// standing job it keeps doing. It moves itself if the moment is bad; to stop one, you tell Kumo.
public struct Job: Sendable, Equatable, Decodable, Identifiable {
    public let id: JobID
    /// Such as "Ask how the QRT interview went".
    public let why: String
    /// When it's next due.
    public let at: Timestamp?
    /// Due after this event ends.
    public let afterEvent: AfterEvent?
    /// What a standing job keeps looking for, such as "startups I'd join".
    public let standing: Standing?
    public let motion: MotionID?

    public struct AfterEvent: Sendable, Equatable, Decodable {
        public let uid: String
        public let title: String
    }

    public struct Standing: Sendable, Equatable, Decodable {
        public let ask: String
    }

    enum CodingKeys: String, CodingKey {
        case id, why, at, standing, motion
        case afterEvent = "after_event"
    }
}

/// The answer to `GET /v0/jobs`: soonest first.
public struct JobList: Sendable, Equatable, Decodable {
    public let jobs: [Job]
}
