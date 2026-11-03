import Foundation

// Kumo's Desk: where Ito opens. It rolls and never resets: Kumo's line and mood, the weather around
// you, Kumo's plans, what's coming up, what's waiting on you, and how much Kumo did without you today.

/// Everything on the Desk at once. It's small, so `desk.changed` carries all of it.
public struct Desk: Sendable, Equatable, Decodable {
    /// Kumo's line and mood, or `nil` until Kumo sets one, or after it clears it.
    public let line: DeskLine?
    /// The weather where you roughly are; `nil` while the box doesn't know where that is, or
    /// couldn't read the weather lately.
    public let ambient: Ambient?
    /// Kumo's plans: every wake-up, soonest first.
    public let plans: [WakeUp]
    /// The next day and a half, and anything big this week, in time order.
    public let comingUp: [CalendarItem]
    /// Drafts, invites, times to check and questions, oldest first, until each is done.
    public let waiting: [DeskCard]
    /// How many things Kumo did without you today.
    public let handled: Int
    /// When Kumo last read a new mail; `nil` while no mail account is connected, and until the
    /// first mail.
    public let lastMailAt: Timestamp?

    public init(
        line: DeskLine? = nil, ambient: Ambient? = nil, plans: [WakeUp] = [],
        comingUp: [CalendarItem] = [], waiting: [DeskCard] = [], handled: Int = 0,
        lastMailAt: Timestamp? = nil
    ) {
        self.line = line
        self.ambient = ambient
        self.plans = plans
        self.comingUp = comingUp
        self.waiting = waiting
        self.handled = handled
        self.lastMailAt = lastMailAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(DeskLine.self, forKey: .line)
        ambient = try container.decodeIfPresent(Ambient.self, forKey: .ambient)
        plans = try container.decodeIfPresent([WakeUp].self, forKey: .plans) ?? []
        comingUp = try container.decode([CalendarItem].self, forKey: .comingUp)
        waiting = try container.decode([DeskCard].self, forKey: .waiting)
        handled = try container.decodeIfPresent(Int.self, forKey: .handled) ?? 0
        lastMailAt = try container.decodeIfPresent(Timestamp.self, forKey: .lastMailAt)
    }

    /// The same Desk with some of its parts changed.
    func with(
        plans: [WakeUp]? = nil, comingUp: [CalendarItem]? = nil, waiting: [DeskCard]? = nil
    ) -> Desk {
        Desk(
            line: line, ambient: ambient, plans: plans ?? self.plans,
            comingUp: comingUp ?? self.comingUp, waiting: waiting ?? self.waiting,
            handled: handled, lastMailAt: lastMailAt)
    }

    /// The same Desk with a card as an answer just left it.
    public func replacing(card: DeskCard) -> Desk {
        with(waiting: waiting.map { $0.id == card.id ? card : $0 })
    }

    /// The same Desk with one of Coming up's items as it is now, such as a guess you answered.
    public func replacing(item: CalendarItem) -> Desk {
        with(comingUp: comingUp.map { $0.id == item.id ? item : $0 })
    }

    /// The same Desk with one of Kumo's plans as it is now, such as one you moved: still soonest
    /// first.
    public func replacing(plan: WakeUp) -> Desk {
        let plans = plans.map { $0.id == plan.id ? plan : $0 }
        return with(plans: plans.sorted { $0.at.date < $1.at.date })
    }

    /// The same Desk with all of Kumo's plans as the box listed them.
    public func replacing(plans: [WakeUp]) -> Desk {
        with(plans: plans)
    }

    /// The same Desk without one of Kumo's plans, such as one you cancelled.
    public func removing(plan: WakeUpID) -> Desk {
        with(plans: plans.filter { $0.id != plan })
    }

    enum CodingKeys: String, CodingKey {
        case line, ambient, plans, waiting, handled
        case comingUp = "coming_up"
        case lastMailAt = "last_mail_at"
    }
}

/// Something interesting at the top of the Desk, by Kumo's judgement: its mood, how something's
/// going, a thought, the day around you. It changes when the moment does, and never notifies.
public struct DeskLine: Sendable, Equatable, Decodable {
    /// A short line, such as "Quiet morning. Your Northwind prep is two-thirds done."
    public let text: String
    /// How Kumo feels, for its face.
    public let mood: KumoMood
    /// When Kumo set it.
    public let at: Timestamp

    public init(text: String, mood: KumoMood = .calm, at: Timestamp) {
        self.text = text
        self.mood = mood
        self.at = at
    }
}

/// How Kumo feels, for its face. One Ari doesn't know shows as calm.
public struct KumoMood: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let bright = KumoMood(rawValue: "bright")
    public static let calm = KumoMood(rawValue: "calm")
    public static let cosy = KumoMood(rawValue: "cosy")
    public static let focused = KumoMood(rawValue: "focused")
    public static let drowsy = KumoMood(rawValue: "drowsy")
    public static let proud = KumoMood(rawValue: "proud")
    public static let concerned = KumoMood(rawValue: "concerned")
    public static let known = [bright, calm, cosy, focused, drowsy, proud, concerned]

    /// The mood to draw: this one, or calm for one Ari doesn't know.
    public var shown: KumoMood { Self.known.contains(self) ? self : .calm }
}

/// The weather where you roughly are, read on the box every half hour or so.
public struct Ambient: Sendable, Equatable, Decodable {
    /// Now, in degrees Celsius, rounded.
    public let temperature: Int
    public let condition: Weather
    /// Whether it's daylight there now.
    public let isDay: Bool
    /// Today's sunset there.
    public let sunset: Timestamp
    /// Where, when the phone named it, such as "Rome".
    public let place: String?

    public init(
        temperature: Int, condition: Weather, isDay: Bool, sunset: Timestamp,
        place: String? = nil
    ) {
        self.temperature = temperature
        self.condition = condition
        self.isDay = isDay
        self.sunset = sunset
        self.place = place
    }

    enum CodingKeys: String, CodingKey {
        case temperature, condition, sunset, place
        case isDay = "is_day"
    }
}

/// The sky, in a word. One Ari doesn't know shows as cloudy.
public struct Weather: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let clear = Weather(rawValue: "clear")
    public static let partlyCloudy = Weather(rawValue: "partly_cloudy")
    public static let cloudy = Weather(rawValue: "cloudy")
    public static let fog = Weather(rawValue: "fog")
    public static let drizzle = Weather(rawValue: "drizzle")
    public static let rain = Weather(rawValue: "rain")
    public static let snow = Weather(rawValue: "snow")
    public static let thunder = Weather(rawValue: "thunder")
    public static let known = [clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunder]

    /// The sky to show: this one, or cloudy for one Ari doesn't know.
    public var shown: Weather { Self.known.contains(self) ? self : .cloudy }
}

/// `GET /v0/work`: Kumo's work for a day, for "47 in: 3 need you, 6 handled, 38 cleared", and the
/// areas it's learning. What needs you is the Desk's `waiting`.
public struct KumoWork: Sendable, Equatable, Decodable {
    /// The local day, such as `2026-11-05`: today, unless you asked for another.
    public let day: String
    /// What Kumo did without you that day, newest first.
    public let handled: [DoneEntry]
    /// The mail Kumo read and left alone that day, newest first.
    public let cleared: [DoneEntry]
    /// Every area Kumo is learning, in the order it opened them, now.
    public let tracks: [Track]

    public init(
        day: String, handled: [DoneEntry] = [], cleared: [DoneEntry] = [], tracks: [Track] = []
    ) {
        self.day = day
        self.handled = handled
        self.cleared = cleared
        self.tracks = tracks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        handled = try container.decode([DoneEntry].self, forKey: .handled)
        cleared = try container.decode([DoneEntry].self, forKey: .cleared)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case day, handled, cleared, tracks
    }
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

    public init(
        id: CardID, kind: CardKind, motion: MotionID? = nil, at: Timestamp,
        changedAt: Timestamp? = nil, title: String, options: [Ask.Option] = [],
        allowsText: Bool = false,
        state: CardState? = nil, answer: CardAnswer? = nil, draft: DraftCard? = nil,
        invite: InviteCard? = nil, times: TimesCard? = nil, question: QuestionCard? = nil,
        offer: OfferCard? = nil
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
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, motion, at, title, options, state, answer, draft, invite, times, question
        case offer
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
    /// The mail's words in light Markdown, formatted as it is in Drafts, without its pictures.
    public let body: String
    /// Your own signature as plain text, added at the end; absent when there's none.
    public let signature: String?
    /// The pictures shown in the mail and the files attached, in order.
    public let attachments: [DraftAttachment]?
    /// The draft's own Message-ID, without angle brackets, for opening it in Mail.
    public let messageID: String
    /// The Message-ID of the mail it answers.
    public let inReplyTo: String?

    public init(
        account: String, from: String, to: [String], cc: [String]? = nil, subject: String,
        body: String, signature: String? = nil, attachments: [DraftAttachment]? = nil,
        messageID: String, inReplyTo: String? = nil
    ) {
        self.account = account
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.signature = signature
        self.attachments = attachments
        self.messageID = messageID
        self.inReplyTo = inReplyTo
    }

    enum CodingKeys: String, CodingKey {
        case account, from, to, cc, subject, body, signature, attachments
        case messageID = "message_id"
        case inReplyTo = "in_reply_to"
    }
}

/// A picture or file in a draft: its name, and whether it shows in the words or rides along.
public struct DraftAttachment: Sendable, Equatable, Decodable {
    public let name: String
    public let kind: AttachmentKind
    public let inline: Bool

    public init(name: String, kind: AttachmentKind, inline: Bool) {
        self.name = name
        self.kind = kind
        self.inline = inline
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
    /// When you said it was wrong.
    public let correctedAt: Timestamp?
    /// The track this call belongs to, when it's in an area Kumo is learning. "That was wrong" on
    /// it steps the track back.
    public let track: TrackID?

    public init(
        id: DoneID, at: Timestamp, text: String, reason: String? = nil, mail: DoneMail? = nil,
        event: CalendarItem? = nil, motion: MotionID? = nil, undo: Bool = false,
        quiet: Bool = false, correctedAt: Timestamp? = nil, track: TrackID? = nil
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
        self.correctedAt = correctedAt
        self.track = track
    }

    /// Whether you've said it was wrong.
    public var isCorrected: Bool { correctedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, at, text, reason, mail, event, motion, undo, quiet, track
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
