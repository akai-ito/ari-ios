// Getting started: Kumo reads your recent mail and calendar and asks you a few questions in the
// conversation, then shows what it found: beliefs to confirm, bookings it added and the things in
// motion it made.

/// Where getting started stands. `onboarding.changed` carries all of it.
public struct Onboarding: Sendable, Equatable, Decodable {
    public let state: OnboardingState
    /// While Kumo reads: how far the catch-up is.
    public let progress: Progress?
    /// Once it's ready: beliefs to confirm, bookings Kumo added and the things in motion it made.
    public let proposal: Proposal?

    public init(state: OnboardingState, progress: Progress? = nil, proposal: Proposal? = nil) {
        self.state = state
        self.progress = progress
        self.proposal = proposal
    }

    public struct Progress: Sendable, Equatable, Decodable {
        public let mailsRead: Int
        public let mailsTotal: Int

        public init(mailsRead: Int, mailsTotal: Int) {
            self.mailsRead = mailsRead
            self.mailsTotal = mailsTotal
        }

        enum CodingKeys: String, CodingKey {
            case mailsRead = "mails_read"
            case mailsTotal = "mails_total"
        }
    }

    public struct Proposal: Sendable, Equatable, Decodable {
        /// With memory from before, a few beliefs to confirm: "Here's what I know. Still true?"
        public let beliefs: [Belief]
        /// Future bookings the catch-up put on your calendar.
        public let added: [CalendarItem]
        /// The things in motion the catch-up made, for "Here's what's in motion". In motion has
        /// each one.
        public let motions: [MotionID]

        public init(beliefs: [Belief] = [], added: [CalendarItem] = [], motions: [MotionID] = []) {
            self.beliefs = beliefs
            self.added = added
            self.motions = motions
        }
    }
}

/// How far getting started is. A state Ari doesn't know means it isn't done.
public struct OnboardingState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Kumo is reading your recent mail and calendar.
    public static let reading = OnboardingState(rawValue: "reading")
    /// The proposal is there.
    public static let ready = OnboardingState(rawValue: "ready")
    /// You've seen what Kumo found, and getting started is over.
    public static let done = OnboardingState(rawValue: "done")
    public static let known = [reading, ready, done]
}

/// A belief's id.
public struct BeliefID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Something Kumo believes about you from memory, for you to confirm or correct before it relies on
/// it.
public struct Belief: Sendable, Equatable, Decodable, Identifiable {
    public let id: BeliefID
    /// Such as "You're training for a sub-20 5K".
    public let text: String
    /// The memory page it comes from.
    public let page: PageAddress
    /// How you answered it; `nil` until you do.
    public let answer: BeliefState?

    public init(id: BeliefID, text: String, page: PageAddress, answer: BeliefState? = nil) {
        self.id = id
        self.text = text
        self.page = page
        self.answer = answer
    }
}

/// How you answered a belief. A state Ari doesn't know means it's answered.
public struct BeliefState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// You said it's true.
    public static let confirmed = BeliefState(rawValue: "true")
    /// Kumo fixed its memory from your correction.
    public static let corrected = BeliefState(rawValue: "corrected")
    public static let known = [confirmed, corrected]
}

/// Your answer to a belief: still true, or a correction in your words.
public enum BeliefAnswer: Sendable, Equatable, Encodable {
    case confirmed
    /// Kumo fixes its memory from it in the background.
    case correction(String)

    private enum CodingKeys: String, CodingKey { case answer, correction }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .confirmed: try container.encode("true", forKey: .answer)
        case .correction(let text): try container.encode(text, forKey: .correction)
        }
    }
}

/// Getting started moved on: all of it.
public struct OnboardingChanged: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let onboarding: Onboarding
}
