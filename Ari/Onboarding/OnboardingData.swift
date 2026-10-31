import AriKit
import Foundation
import Observation

// What onboarding shows, as the app holds it. The box's onboarding API isn't settled yet, so these
// are the app's own shapes: whoever backs `OnboardingModel` (the server, or a preview) fills them in
// and answers its closures.

/// How far Kumo has got reading the last three months of mail: "Reading… 1,240 of 3,100 mails".
struct OnboardingProgress: Equatable, Sendable {
    var read: Int
    /// How many mails there are to read; 0 while Kumo is still counting them.
    var total: Int

    var isDone: Bool { total > 0 && read >= total }
    var fraction: Double { total > 0 ? min(1, Double(read) / Double(total)) : 0 }

    /// The line itself, such as "Reading… 1,240 of 3,100 mails".
    var words: String {
        if total == 0 { return "Reading your mail…" }
        let mails = total == 1 ? "mail" : "mails"
        if isDone { return "Read all \(total.formatted()) \(mails)" }
        return "Reading… \(read.formatted()) of \(total.formatted()) \(mails)"
    }

    /// The same, as VoiceOver says it.
    var spoken: String {
        if total == 0 { return "Reading your mail" }
        if isDone { return "Read all \(total.formatted()) mails" }
        return "Reading \(read.formatted()) of \(total.formatted()) mails"
    }
}

/// One thing Kumo asks while it reads, such as what's going on in your life right now.
struct KumoQuestion: Hashable, Identifiable, Sendable {
    let id: String
    /// In Kumo's words.
    let text: String
}

/// Something Kumo already believes about you, for someone who comes with memory: "You're in QRT's
/// interview process".
struct Belief: Equatable, Identifiable, Sendable {
    let id: String
    let text: String
}

/// Something Kumo found in motion in your life, such as the job search or a trip: its title, where
/// it stands, and its symbol.
struct RevealMatter: Equatable, Identifiable, Sendable {
    let id: String
    /// Such as "Job search".
    let title: String
    /// Where it stands, such as "QRT awaiting · Citadel Tue 17".
    let line: String
    /// Its SF Symbol, as In motion draws its kind.
    let symbol: String
}

/// Something the catch-up put on your calendar, such as a booking that wasn't there.
struct AddedEvent: Equatable, Sendable {
    let title: String
    /// Already written for reading, such as "Thu 12 Nov · 22:10".
    let when: String
}

/// Somewhere Kumo can read from: iCloud for Mail and Calendar, Outlook, Gmail.
struct ConnectableSource: Equatable, Identifiable, Sendable {
    /// The capability or source it sets up, such as `icloud`.
    let id: String
    let title: String
    /// What it brings, such as "Mail and Calendar".
    let detail: String
    var connected: Bool
    /// Its SF Symbol.
    var symbol = "envelope"
}

/// What Kumo found, for the last step: what's in motion and what it added to your calendar.
struct OnboardingReveal: Equatable, Sendable {
    var matters: [RevealMatter]
    var added: [AddedEvent] = []
}

/// Where Kumo's questions are: choosing the next, asking one, or done asking.
enum KumoAsking: Hashable, Sendable {
    /// Kumo is choosing its first question, or the next.
    case waiting
    case asking(KumoQuestion)
    /// Kumo has what it needs for now.
    case finished
}

/// Your answer to one of Kumo's beliefs.
enum BeliefReply: Equatable, Sendable {
    case stillTrue
    /// Not any more, with what's true now; empty when it simply ended.
    case corrected(String)
}

/// Where notifications stand once you've been asked.
enum NotificationsChoice: Equatable, Sendable {
    case allowed
    /// You asked, and iOS has them off: Settings is the way back.
    case off
    /// You chose Not now.
    case notNow
}

/// What onboarding does, each through whoever backs it. Every one that talks to the box is async
/// and throws, so its button can spin and a failure shows in a line.
struct OnboardingActions {
    /// Opens a source's setup sheet. The backer marks it connected in `sources` once it is.
    var connect: (ConnectableSource) -> Void
    /// Starts a call with Kumo, to answer the question in your voice. Kumo's next question arrives
    /// by setting `asking`.
    var talk: () -> Void
    /// Sends an answer to a question; returns Kumo's next question, or `nil` once it has enough.
    var answer: (KumoQuestion.ID, String) async throws -> KumoQuestion?
    /// Passes on a question; returns the next, or `nil`.
    var skip: (KumoQuestion.ID) async throws -> KumoQuestion?
    /// One of Kumo's beliefs is still true.
    var confirm: (Belief.ID) async throws -> Void
    /// One isn't any more, with what's true now (empty when it simply ended).
    var correct: (Belief.ID, String) async throws -> Void
    /// The morning's "not before" time, as an hour and minute.
    var setMorning: (DateComponents) async throws -> Void
    /// Asks iOS for notifications; `true` if they're on.
    var allowNotifications: () async -> Bool
    /// You chose Not now.
    var declineNotifications: () -> Void
    /// Onboarding is done: opens the Desk.
    var finish: () async throws -> Void
}

/// Onboarding, right after pairing: five calm steps, each one idea, building to the reveal. Its
/// data comes from whoever backs it (set the properties as things change, such as `progress` while
/// Kumo reads, or `reveal` once it has caught up), and everything you do goes through `actions`.
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable, Comparable, Sendable {
        /// The character wakes, with one line and three promises.
        case meet
        /// Mail and calendar.
        case connect
        /// Kumo's questions while it reads, or "Still true?" for someone with memory.
        case knowYou
        /// The morning's "not before" time and notifications.
        case morning
        /// What's in motion and what Kumo added; Open the Desk.
        case reveal

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var step: Step
    var sources: [ConnectableSource]
    /// Kumo reading the last three months; `nil` until something is connected.
    var progress: OnboardingProgress?
    var asking: KumoAsking
    /// What Kumo already believes about you. Any at all turns Kumo's questions into "Still true?".
    var beliefs: [Belief]
    /// The morning's "not before" time.
    var morning: DateComponents
    /// `nil` until you've chosen, or already decided if iOS has an answer.
    var notifications: NotificationsChoice?
    /// What Kumo found; `nil` while it's still catching up.
    var reveal: OnboardingReveal?

    private(set) var replies: [Belief.ID: BeliefReply] = [:]

    @ObservationIgnored let actions: OnboardingActions

    init(
        step: Step = .meet, sources: [ConnectableSource], progress: OnboardingProgress? = nil,
        asking: KumoAsking = .waiting, beliefs: [Belief] = [],
        morning: DateComponents = DateComponents(hour: 7, minute: 30),
        notifications: NotificationsChoice? = nil, reveal: OnboardingReveal? = nil,
        actions: OnboardingActions
    ) {
        self.step = step
        self.sources = sources
        self.progress = progress
        self.asking = asking
        self.beliefs = beliefs
        self.morning = morning
        self.notifications = notifications
        self.reveal = reveal
        self.actions = actions
    }

    var anyConnected: Bool { sources.contains(where: \.connected) }

    /// Someone who comes with memory, such as Divy: Kumo checks what it knows instead of asking.
    var knowsYou: Bool { !beliefs.isEmpty }

    func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    // MARK: Kumo's questions

    func answer(_ text: String) async throws {
        guard case .asking(let question) = asking else { return }
        let next = try await actions.answer(question.id, text)
        asking = next.map(KumoAsking.asking) ?? .finished
    }

    func skipQuestion() async throws {
        guard case .asking(let question) = asking else { return }
        let next = try await actions.skip(question.id)
        asking = next.map(KumoAsking.asking) ?? .finished
    }

    // MARK: Still true?

    func confirm(_ belief: Belief) async throws {
        try await actions.confirm(belief.id)
        replies[belief.id] = .stillTrue
    }

    func correct(_ belief: Belief, to text: String) async throws {
        try await actions.correct(belief.id, text)
        replies[belief.id] = .corrected(text)
    }

    /// Back to the question, to answer it again.
    func reopen(_ belief: Belief) {
        replies[belief.id] = nil
    }

    // MARK: Morning and notifications

    func saveMorning() async throws {
        try await actions.setMorning(morning)
    }

    func allowNotifications() async {
        notifications = await actions.allowNotifications() ? .allowed : .off
    }

    func declineNotifications() {
        actions.declineNotifications()
        notifications = .notNow
    }

    // MARK: The reveal

    func finish() async throws {
        try await actions.finish()
    }
}
