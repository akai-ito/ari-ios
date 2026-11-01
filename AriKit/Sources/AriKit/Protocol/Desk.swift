import Foundation

// Kumo's Desk: where Ito opens. It rolls and never resets: Kumo's line for the moment, what's coming
// up, what's waiting on you, and how much Kumo did without you today.

/// Everything on the Desk at once. It's small, so `desk.changed` carries all of it.
public struct Desk: Sendable, Equatable, Decodable {
    /// Kumo's line for the moment, or `nil` while all is quiet.
    public let moment: Moment?
    /// The next day and a half, and anything big this week, in time order.
    public let comingUp: [CalendarItem]
    /// Drafts, invites, times to check and questions, oldest first, until each is done.
    public let waiting: [DeskCard]
    /// How many things Kumo did without you today, for "Done · handled 9".
    public let handled: Int
    /// When Kumo last read a new mail, for "Reading · last mail 2 min ago"; `nil` while no mail
    /// account is connected, and until the first mail.
    public let lastMailAt: Timestamp?

    public init(
        moment: Moment? = nil, comingUp: [CalendarItem] = [], waiting: [DeskCard] = [],
        handled: Int = 0, lastMailAt: Timestamp? = nil
    ) {
        self.moment = moment
        self.comingUp = comingUp
        self.waiting = waiting
        self.handled = handled
        self.lastMailAt = lastMailAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moment = try container.decodeIfPresent(Moment.self, forKey: .moment)
        comingUp = try container.decode([CalendarItem].self, forKey: .comingUp)
        waiting = try container.decode([DeskCard].self, forKey: .waiting)
        handled = try container.decodeIfPresent(Int.self, forKey: .handled) ?? 0
        lastMailAt = try container.decodeIfPresent(Timestamp.self, forKey: .lastMailAt)
    }

    /// The same Desk with a card, or Kumo's line, as an answer just left them.
    public func replacing(card: DeskCard? = nil, moment replaced: Moment? = nil) -> Desk {
        Desk(
            moment: replaced.flatMap { $0.id == moment?.id ? $0 : nil } ?? moment,
            comingUp: comingUp,
            waiting: waiting.map { $0.id == card?.id ? card ?? $0 : $0 },
            handled: handled, lastMailAt: lastMailAt)
    }

    /// The same Desk with one of Coming up's items as it is now, such as a guess you answered.
    public func replacing(item: CalendarItem) -> Desk {
        Desk(
            moment: moment, comingUp: comingUp.map { $0.id == item.id ? item : $0 },
            waiting: waiting, handled: handled, lastMailAt: lastMailAt)
    }

    /// The same Desk once Kumo's line has gone, such as the day's question you skipped.
    public func withoutMoment(_ id: MomentID) -> Desk {
        Desk(
            moment: moment?.id == id ? nil : moment, comingUp: comingUp, waiting: waiting,
            handled: handled, lastMailAt: lastMailAt)
    }

    enum CodingKeys: String, CodingKey {
        case moment, waiting, handled
        case comingUp = "coming_up"
        case lastMailAt = "last_mail_at"
    }
}

/// The id of one of Kumo's lines for the moment.
public struct MomentID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Kumo's line for the moment, at the top of the Desk: one or two sentences, right for now, which
/// order and connect what's below rather than repeat it. The same words are a message in the
/// conversation. It goes three hours after it was read, at midnight, or once Kumo has acted on your
/// answer, and then all is quiet.
public struct Moment: Sendable, Equatable, Decodable, Identifiable {
    public let id: MomentID
    public let kind: MomentKind
    public let at: Timestamp
    /// One or two sentences, plain words.
    public let text: String
    /// A quieter line under the words, such as the plan under a free day. The message holds it
    /// too, after the words.
    public let detail: String?
    /// The message in the conversation that holds the same words.
    public let message: MessageID
    /// Up to three short replies, such as "Ask me tonight". A tap answers Kumo, like a card.
    public let options: [Ask.Option]
    /// Whether a typed reply fits, for Reply.
    public let allowsText: Bool
    /// What Reply says when words fit, such as "Note it"; Reply when `nil`.
    public let replyLabel: String?
    /// When an app first showed it on the Desk. Once read, no notification goes out for it.
    public let readAt: Timestamp?
    /// `working` while Kumo acts on your answer.
    public let state: CardState?
    /// While it's `working`: the answer you gave.
    public let answer: CardAnswer?

    public init(
        id: MomentID, kind: MomentKind = .news, at: Timestamp, text: String,
        detail: String? = nil, message: MessageID, options: [Ask.Option] = [],
        allowsText: Bool = false, replyLabel: String? = nil, readAt: Timestamp? = nil,
        state: CardState? = nil, answer: CardAnswer? = nil
    ) {
        self.id = id
        self.kind = kind
        self.at = at
        self.text = text
        self.detail = detail
        self.message = message
        self.options = options
        self.allowsText = allowsText
        self.replyLabel = replyLabel
        self.readAt = readAt
        self.state = state
        self.answer = answer
    }

    /// Whether Kumo is acting on your answer.
    public var isWorking: Bool { state == .working }

    enum CodingKeys: String, CodingKey {
        case id, kind, at, text, detail, message, options, state, answer
        case allowsText = "allows_text"
        case replyLabel = "reply_label"
        case readAt = "read_at"
    }
}

/// What brought Kumo's line. A kind Ari doesn't know draws like any other.
public struct MomentKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The first line of the day, at the first calm moment after your morning time.
    public static let day = MomentKind(rawValue: "day")
    /// Something that matters arrived.
    public static let news = MomentKind(rawValue: "news")
    /// Your day changed.
    public static let change = MomentKind(rawValue: "change")
    /// A commitment you made, such as when you'd stop tonight, coming due.
    public static let checkin = MomentKind(rawValue: "checkin")
    /// Your week's time drifting from what matters.
    public static let drift = MomentKind(rawValue: "drift")
    /// The day's one small question, which you can skip.
    public static let question = MomentKind(rawValue: "question")
    public static let known = [day, news, change, checkin, drift, question]
}

/// The body that skips the day's question: it goes at once, and Kumo never asks it again.
public struct MomentSkip: Sendable, Equatable, Codable {
    public let skip: Bool

    public init() { skip = true }
}

/// `POST /v0/desk/moment/{id}/answer`'s answer: Kumo's line, `working` with your answer.
public struct MomentResult: Sendable, Equatable, Decodable {
    public let moment: Moment
}

/// `GET /v0/work`: Kumo's work for a day, for "47 in: 3 need you, 6 handled, 38 cleared", and how
/// much it checks with you. What needs you is the Desk's `waiting`.
public struct KumoWork: Sendable, Equatable, Decodable {
    /// The local day, such as `2026-11-05`: today, unless you asked for another.
    public let day: String
    /// What Kumo did without you that day, newest first.
    public let handled: [DoneEntry]
    /// The mail Kumo read and left alone that day, newest first.
    public let cleared: [DoneEntry]
    /// The trust ladder: each kind of work Kumo has done, on its rung, in a fixed order.
    public let trust: [TrustRung]

    public init(
        day: String, handled: [DoneEntry] = [], cleared: [DoneEntry] = [], trust: [TrustRung] = []
    ) {
        self.day = day
        self.handled = handled
        self.cleared = cleared
        self.trust = trust
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        handled = try container.decode([DoneEntry].self, forKey: .handled)
        cleared = try container.decode([DoneEntry].self, forKey: .cleared)
        trust = try container.decodeIfPresent([TrustRung].self, forKey: .trust) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case day, handled, cleared, trust
    }
}

/// A kind of Kumo's work, each with its own rung on the trust ladder. A kind Ari doesn't know shows
/// by the title Kumo's work gives it.
public struct WorkKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The mail Kumo files, bins and clears.
    public static let sorting = WorkKind(rawValue: "sorting")
    /// What Kumo puts on, moves or takes off your calendars.
    public static let calendar = WorkKind(rawValue: "calendar")
    /// The replies Kumo writes for you.
    public static let drafts = WorkKind(rawValue: "drafts")
    /// What Kumo changes in your contacts.
    public static let contacts = WorkKind(rawValue: "contacts")
    public static let known = [sorting, calendar, drafts, contacts]
}

/// How much Kumo checks with you for one kind of work: Learning, then Spot checks, then Trusted. It
/// climbs after a clean stretch, and a "That was wrong" steps it back one.
public struct TrustRung: Sendable, Equatable, Decodable, Identifiable {
    public var id: WorkKind { work }
    public let work: WorkKind
    /// Its name, such as "Sorting mail".
    public let title: String
    public let step: TrustStep
    /// Kumo's line on where it stands and why, such as "Two weeks without a correction on sorting."
    public let line: String
    /// When its current stretch began: its first call, a climb, a correction or a reset.
    public let since: Timestamp

    public init(work: WorkKind, title: String, step: TrustStep, line: String, since: Timestamp) {
        self.work = work
        self.title = title
        self.step = step
        self.line = line
        self.since = since
    }
}

/// A rung on the trust ladder. One Ari doesn't know shows as Learning.
public struct TrustStep: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Kumo shows you its calls, with a card a day to glance at them.
    public static let learning = TrustStep(rawValue: "learning")
    /// About one call in five may get a quiet "Was this right?" card.
    public static let spotChecks = TrustStep(rawValue: "spot_checks")
    /// Only what needs you.
    public static let trusted = TrustStep(rawValue: "trusted")
    public static let known = [learning, spotChecks, trusted]

    /// Where it stands, from 0 for Learning to 2 for Trusted.
    public var rung: Int { Self.known.firstIndex(of: self) ?? 0 }
}

/// `POST /v0/trust/{work}/reset`'s answer: the kind, back to Learning.
public struct TrustResult: Sendable, Equatable, Decodable {
    public let trust: TrustRung
}

/// The body of `POST /v0/done/{entry}/wrong`: what was wrong in your words, or nothing.
public struct CorrectDone: Sendable, Equatable, Codable {
    public let text: String?

    public init(text: String? = nil) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed?.isEmpty == false ? trimmed : nil
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
    /// When Kumo last changed it while it waited, such as rewriting a draft.
    public let changedAt: Timestamp?
    /// One line, such as "Draft to Tess".
    public let title: String
    /// The buttons to draw, in order. Answering with one sends its label.
    public let options: [Ask.Option]
    /// Whether words work as an answer too; for a draft, they ask for a change.
    public let allowsText: Bool
    /// `working` while the box acts on your answer, such as rewriting a draft.
    public let state: CardState?
    /// While it's `working`: the answer you gave, as you gave it.
    public let answer: CardAnswer?
    public let draft: DraftCard?
    public let invite: InviteCard?
    public let times: TimesCard?
    public let question: QuestionCard?
    public let offer: OfferCard?
    /// On a question: Kumo is still learning, so it asks you to glance at a day's calls. Its first
    /// option opens Kumo's work for that day, showing only these kinds of work.
    public let review: ReviewCard?

    public init(
        id: CardID, kind: CardKind, motion: MotionID? = nil, at: Timestamp,
        changedAt: Timestamp? = nil, title: String, options: [Ask.Option] = [],
        allowsText: Bool = false,
        state: CardState? = nil, answer: CardAnswer? = nil, draft: DraftCard? = nil,
        invite: InviteCard? = nil, times: TimesCard? = nil, question: QuestionCard? = nil,
        offer: OfferCard? = nil, review: ReviewCard? = nil
    ) {
        self.id = id
        self.kind = kind
        self.motion = motion
        self.at = at
        self.changedAt = changedAt
        self.title = title
        self.options = options
        self.allowsText = allowsText
        self.state = state
        self.answer = answer
        self.draft = draft
        self.invite = invite
        self.times = times
        self.question = question
        self.offer = offer
        self.review = review
    }

    /// Whether answering with this option opens Kumo's work to glance at a day's calls.
    public func glances(_ answer: CardAnswer) -> Bool {
        review != nil && answer.option != nil && answer.option == options.first?.label
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, motion, at, title, options, state, answer, draft, invite, times, question
        case offer, review
        case allowsText = "allows_text"
        case changedAt = "changed_at"
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
    /// What the times are for, such as "A call with Tess".
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

/// A day of Kumo's calls to glance at while it's learning: the day, for `GET /v0/work?day=`, and
/// the kinds of work to show.
public struct ReviewCard: Sendable, Equatable, Decodable {
    public let day: String
    public let work: [WorkKind]

    public init(day: String, work: [WorkKind]) {
        self.day = day
        self.work = work
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
    /// Only on Kumo's guesses at your day: what Kumo thinks you'll be doing, and why.
    public let guess: Guess?

    public init(
        id: CalendarItemID, uid: String, title: String, start: When, end: When,
        allDay: Bool = false, location: String? = nil, calendar: CalendarName,
        leaveAt: Timestamp? = nil, motion: MotionID? = nil, status: CalendarStatus? = nil,
        guess: Guess? = nil
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
        self.guess = guess
    }

    enum CodingKeys: String, CodingKey {
        case id, uid, title, start, end, location, calendar, motion, status, guess
        case allDay = "all_day"
        case leaveAt = "leave_at"
    }
}

/// Kumo's guess at what you're doing then, from your past weeks, what you've said and what it
/// can see. Once you've answered it, it's yours rather than a guess.
public struct Guess: Sendable, Equatable, Decodable {
    public let activity: Activity
    /// Why Kumo thinks so, such as "Your usual weekday at the desk, from the last four weeks."
    public let why: String

    public init(activity: Activity, why: String) {
        self.activity = activity
        self.why = why
    }
}

/// What you're doing, in Kumo's picture of your day. One Ari doesn't know shows by its title.
public struct Activity: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let working = Activity(rawValue: "working")
    public static let building = Activity(rawValue: "building")
    public static let training = Activity(rawValue: "training")
    /// Seeing people.
    public static let people = Activity(rawValue: "people")
    public static let studying = Activity(rawValue: "studying")
    public static let chilling = Activity(rawValue: "chilling")
    /// Something else, named in the title.
    public static let other = Activity(rawValue: "other")
    public static let known = [working, building, training, people, studying, chilling, other]
}

/// Your answer to one of Kumo's guesses: it was right, the activity it really was, or a few words
/// for something else, which become its title.
public struct GuessAnswer: Sendable, Equatable, Codable {
    public let right: Bool?
    public let activity: Activity?
    public let text: String?

    /// The guess was right.
    public static let right = GuessAnswer(right: true, activity: nil, text: nil)

    /// It was something else you do.
    public init(activity: Activity) {
        self.init(right: nil, activity: activity, text: nil)
    }

    /// It was something else, in your words.
    public init(text: String) {
        self.init(right: nil, activity: nil, text: text)
    }

    private init(right: Bool?, activity: Activity?, text: String?) {
        self.right = right
        self.activity = activity
        self.text = text
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

/// One thing Kumo did without you. "That was wrong" on it undoes it where it can, and Kumo keeps
/// what to do differently as a preference.
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
    /// The kind of work, when it was one of Kumo's own calls: what the trust ladder counts.
    public let work: WorkKind?
    /// When you said it was wrong.
    public let correctedAt: Timestamp?

    public init(
        id: DoneID, at: Timestamp, text: String, reason: String? = nil, mail: DoneMail? = nil,
        event: CalendarItem? = nil, motion: MotionID? = nil, undo: Bool = false,
        quiet: Bool = false, work: WorkKind? = nil, correctedAt: Timestamp? = nil
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
        self.work = work
        self.correctedAt = correctedAt
    }

    /// Whether you've said it was wrong.
    public var isCorrected: Bool { correctedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, at, text, reason, mail, event, motion, undo, quiet, work
        case correctedAt = "corrected_at"
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
    /// Such as "Ask how the Halcyon interview went".
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
