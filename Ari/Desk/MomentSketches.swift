#if DEBUG
    import AriKit
    import SwiftUI

    /// The Desk at each of Kumo's moments, from the "Kumo's moments" design round, drawn from
    /// samples without a server: `ARI_SKETCH=<name>` opens the app on one. Everyone and everything
    /// in them is made up.
    enum MomentSketch: String, CaseIterable {
        /// A free Sunday morning, with the plan under it.
        case sunday
        /// 00:45, fifteen minutes to the line you set.
        case commit
        /// 01:10, past the line: firmer.
        case pastLine = "past-line"
        /// After an event: how did it go?
        case afterEvent = "after-event"
        /// A quiet afternoon.
        case quiet
        /// Something's wrong on the server.
        case wrong
        /// Kumo's work, opened from its face.
        case work
        /// Kumo's work, down at how much it checks with you.
        case workTrust = "work-trust"
        /// A weekday's Coming up, with Kumo's soft blocks and its guesses.
        case guesses
        /// The day's one question.
        case question

        typealias S = MomentSamples

        var moment: KumoMoment? {
            switch self {
            case .sunday:
                KumoMoment(
                    id: "sunday", text: "A free Sunday, with a quiet plan under it.",
                    detail:
                        "Easy run (week 1 of 6) · groceries and proper meals · 2h coding prep · in bed by 00:30 so Monday works",
                    actions: [.init(title: "Change it", opens: true)])
            case .commit:
                KumoMoment(
                    id: "commit",
                    text:
                        "15 minutes to your 1. Note the next step now? Tomorrow's run and prep still fit if you're asleep by 1:30.",
                    actions: [.init(title: "Note it", opens: true), .init(title: "Snooze 15m")])
            case .pastLine:
                KumoMoment(
                    id: "past-line",
                    text:
                        "Every half hour now comes out of tomorrow's run or the interview prep. Your call. Which?",
                    actions: [
                        .init(title: "The run"), .init(title: "The prep"),
                        .init(title: "I'm stopping"),
                    ])
            case .afterEvent, .work, .workTrust:
                KumoMoment(
                    id: "after-northwind", text: "How did the call with Northwind go?",
                    actions: [.init(title: "Reply", opens: true), .init(title: "Ask me tonight")])
            case .quiet:
                KumoMoment(id: "quiet", text: "All quiet. I handled 9 small things.")
            case .wrong:
                KumoMoment(
                    id: "sam-moved",
                    text: "Sam moved climbing to 8, so I've moved your prep to 6.")
            case .guesses:
                KumoMoment(
                    id: "big-day", text: "Big one at 2. Everything else can bend around it.")
            case .question:
                KumoMoment(
                    id: "question",
                    text:
                        "Is Thursday climbing with Sam something I should guard, or fine to move when work piles up?",
                    actions: [.init(title: "Guard it"), .init(title: "Fine to move")], asks: true)
            }
        }

        var liveness: KumoLiveness {
            switch self {
            case .wrong: .wrong
            case .commit, .pastLine: .reading(lastMail: .now.addingTimeInterval(-38 * 60))
            default: .reading(lastMail: .now.addingTimeInterval(-150))
            }
        }

        var problems: [ServerProblem] {
            self == .wrong ? [ProblemSamples.outlook] : []
        }

        var comingUp: [CalendarItem] {
            switch self {
            case .sunday: S.sunday
            case .commit, .pastLine: S.lateNight
            case .afterEvent, .work, .workTrust, .question: S.evening
            case .quiet: S.quietAfternoon
            case .wrong: S.wrongDay
            case .guesses: S.weekday
            }
        }

        var waiting: [DeskCard] {
            switch self {
            case .sunday: [S.priyaDraft, S.halcyonTimes]
            case .commit, .pastLine: [S.priyaDraft]
            case .afterEvent, .work, .workTrust: [S.thanksDraft, S.halcyonTimes, S.samInvite]
            case .quiet: []
            case .wrong, .guesses: [S.halcyonTimes, S.samInvite]
            case .question: [S.thanksDraft, S.halcyonTimes]
            }
        }

        var changed: Set<CardID> {
            switch self {
            case .sunday: ["priya-draft"]
            case .afterEvent, .work, .workTrust, .question: ["halcyon-times"]
            case .wrong: ["sam-invite"]
            default: []
            }
        }

        var handled: Int { 9 }

        /// The status bar's time for the still, so it matches the moment.
        var clock: String {
            switch self {
            case .sunday: "9:10"
            case .commit: "00:45"
            case .pastLine: "01:10"
            case .afterEvent, .work, .workTrust: "15:20"
            case .quiet: "15:40"
            case .wrong: "11:30"
            case .guesses: "8:20"
            case .question: "19:05"
            }
        }
    }

    /// The Desk as a sketch: the real pieces, from samples, in the app's tabs.
    struct MomentSketchRoot: View {
        let sketch: MomentSketch
        @State private var place = 0

        var body: some View {
            TabView(selection: $place) {
                Tab("Desk", systemImage: "rectangle.grid.1x2", value: 0) {
                    MomentSketchDesk(sketch: sketch)
                }
                Tab("Chat", systemImage: "bubble.left", value: 1) { Color.ariBackground }
                Tab("In motion", systemImage: "circle.dotted.circle", value: 2) {
                    Color.ariBackground
                }
                Tab("You", systemImage: "person.crop.circle", value: 3) { Color.ariBackground }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        }
    }

    private struct MomentSketchDesk: View {
        let sketch: MomentSketch

        @State private var draft = ""
        @State private var showsWork = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    KumoSays(
                        moment: sketch.moment, liveness: sketch.liveness,
                        openWork: { showsWork = true }, openSettings: {}, openProblem: {})
                    if !sketch.problems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sketch.problems) { problem in ProblemLine(problem: problem) {} }
                        }
                        .padding(.horizontal, 4)
                    }
                    if !sketch.comingUp.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            DeskSectionLabel("Coming up")
                            ComingUpList(
                                items: sketch.comingUp, open: { _ in },
                                guess: { MomentSamples.guesses[$0.id] },
                                unfoldedGuess: sketch == .guesses ? "g-work-am" : nil)
                        }
                    }
                    if !sketch.waiting.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            DeskSectionLabel("Waiting on you", trailing: "\(sketch.waiting.count)")
                            WaitingList(
                                cards: sketch.waiting, open: { _ in }, answer: { _, _ in },
                                changed: sketch.changed)
                        }
                    }
                    DeskDoneLine(handled: sketch.handled) { showsWork = true }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(
                    draft: $draft, role: .idle, prompt: "Tell \(LeadName.current)…", send: {},
                    stop: {}, talk: {}, talkReady: true
                )
                .background(.ariBackground)
            }
            .sheet(isPresented: $showsWork) {
                NavigationStack {
                    KumosWorkView(
                        ledger: MomentSamples.ledger, wrong: { _ in }, openAll: {},
                        opensAtTrust: sketch == .workTrust)
                }
                .presentationDetents([.large])
            }
            .task {
                if sketch == .work || sketch == .workTrust {
                    try? await Task.sleep(for: .milliseconds(400))
                    showsWork = true
                }
            }
        }
    }

    /// The made-up life the sketches show: Northwind and Halcyon are companies, Priya a recruiter,
    /// Sam a friend.
    enum MomentSamples {
        private static let home = CalendarName(name: "Home")
        private static let kumo = CalendarName(name: "Kumo", kumo: true)
        private static func at(day: Int = 0, _ hour: Int, _ minute: Int = 0) -> Timestamp {
            DeskSamples.at(day: day, hour, minute)
        }
        private static func when(day: Int = 0, _ hour: Int, _ minute: Int = 0) -> When {
            DeskSamples.when(day: day, hour, minute)
        }

        private static func block(
            _ id: String, _ title: String, day: Int = 0, _ hour: Int, _ minute: Int = 0,
            hours: Double = 1
        ) -> CalendarItem {
            let start = DeskSamples.at(day: day, hour, minute).date
            return CalendarItem(
                id: CalendarItemID(rawValue: id), uid: "\(id)@kumo", title: title,
                start: When(start), end: When(start.addingTimeInterval(hours * 3600)),
                calendar: kumo)
        }

        private static func event(
            _ id: String, _ title: String, day: Int = 0, _ hour: Int, _ minute: Int = 0,
            hours: Double = 1, location: String? = nil
        ) -> CalendarItem {
            let start = DeskSamples.at(day: day, hour, minute).date
            return CalendarItem(
                id: CalendarItemID(rawValue: id), uid: "\(id)@icloud", title: title,
                start: When(start), end: When(start.addingTimeInterval(hours * 3600)),
                location: location, calendar: home)
        }

        /// Kumo's guesses at your day, with why it thinks so.
        static let guesses: [CalendarItemID: String] = [
            "g-work-am": "Your usual weekday at the desk, from the last four weeks.",
            "g-work-pm": "You're usually heads-down after lunch on weekdays.",
            "g-build": "Most weeknights this month you've been building after dinner.",
            "g-chill": "After climbing you usually switch off.",
            "g-people": "Thursdays are often dinner with friends.",
            "g-work-tmrw": "Your usual weekday at the desk, from the last four weeks.",
        ]

        // MARK: Coming up

        static let sunday = [
            block("s-run", "Easy run, week 1 of 6", 10, 30, hours: 0.5),
            block("s-shop", "Groceries", 12, 0),
            block("s-cook", "Cook a proper lunch", 13, 0),
            block("s-prep", "Coding prep, 2h", 15, 0, hours: 2),
            event("s-mum", "Call Mum", 18, 0, hours: 0.5),
            block("s-wind", "Wind down", 23, 45, hours: 0.75),
            event("s-northwind", "Northwind intro call", day: 1, 14, 0, location: "Teams"),
        ]

        static let lateNight = [
            block("n-run", "Easy run, week 1 of 6", 7, 45, hours: 0.5),
            CalendarItem(
                id: "g-work-am", uid: "g-work-am@kumo", title: "Working", start: when(9, 30),
                end: when(12, 30), calendar: kumo),
            block("n-lunch", "Proper lunch", 12, 30),
            event("n-northwind", "Northwind intro call", 14, 0, location: "Teams"),
            block("n-prep", "Interview prep, 1h", 18, 30),
        ]

        static let evening = [
            block("e-prep", "Interview prep, 1h", 18, 0),
            event("e-climb", "Climbing with Sam", 20, 0, hours: 2, location: "The Boulder Shed"),
            CalendarItem(
                id: "g-chill", uid: "g-chill@kumo", title: "Chilling", start: when(22, 0),
                end: when(23, 30), calendar: kumo),
            block("e-wind", "Wind down", 23, 30, hours: 0.75),
            event("e-halcyon", "Halcyon, second call", day: 1, 11, 0, location: "Zoom"),
        ]

        static let quietAfternoon = [
            block("q-prep", "Interview prep, 1h", 18, 0),
            event("q-dinner", "Dinner with Sam", 19, 30, hours: 2, location: "The Larder"),
            block("q-wind", "Wind down", 23, 30, hours: 0.75),
        ]

        static let wrongDay = [
            CalendarItem(
                id: "g-work-am", uid: "g-work-am@kumo", title: "Working", start: when(9, 30),
                end: when(12, 30), calendar: kumo),
            block("w-lunch", "Proper lunch", 12, 30),
            block("w-prep", "Interview prep, 1h", 18, 0),
            event("w-climb", "Climbing with Sam", 20, 0, hours: 2, location: "The Boulder Shed"),
        ]

        static let weekday = [
            block("d-run", "Easy run, week 1 of 6", 7, 30, hours: 0.5),
            CalendarItem(
                id: "g-work-am", uid: "g-work-am@kumo", title: "Working", start: when(9, 0),
                end: when(12, 0), calendar: kumo),
            block("d-prep", "Prep: Northwind, 1h", 12, 0),
            block("d-lunch", "Proper lunch", 13, 0, hours: 0.5),
            event("d-northwind", "Northwind intro call", 14, 0, location: "Teams"),
            CalendarItem(
                id: "g-work-pm", uid: "g-work-pm@kumo", title: "Working", start: when(15, 0),
                end: when(18, 0), calendar: kumo),
            CalendarItem(
                id: "g-build", uid: "g-build@kumo", title: "Building", start: when(19, 30),
                end: when(21, 30), calendar: kumo),
            CalendarItem(
                id: "g-chill", uid: "g-chill@kumo", title: "Chilling", start: when(21, 30),
                end: when(23, 15), calendar: kumo),
            block("d-wind", "Wind down", 23, 15, hours: 0.75),
            event("d-dentist", "Dentist", day: 1, 9, 0, location: "Bright Smile"),
            CalendarItem(
                id: "g-people", uid: "g-people@kumo", title: "Seeing people",
                start: when(day: 1, 19, 0), end: when(day: 1, 22, 0), calendar: kumo),
        ]

        // MARK: Cards

        static let priyaDraft = DeskCard(
            id: "priya-draft", kind: .draft, at: at(8, 2), title: "Draft to Priya at Northwind",
            draft: DraftCard(
                account: "iCloud", from: "you@icloud.example", to: ["Priya Raman"],
                subject: "Re: Intro call on Monday",
                body: "Hi Priya! Monday at 2 is perfect, Teams works. Speak then :)",
                messageID: "draft-a1@icloud.example"))

        static let thanksDraft = DeskCard(
            id: "thanks-draft", kind: .draft, at: at(15, 5), title: "Draft to Priya at Northwind",
            draft: DraftCard(
                account: "iCloud", from: "you@icloud.example", to: ["Priya Raman"],
                subject: "Thanks for today",
                body: "Thanks for the time today, Priya! Really enjoyed hearing about the team.",
                messageID: "draft-b2@icloud.example"))

        static let halcyonTimes = DeskCard(
            id: "halcyon-times", kind: .times, at: at(9, 40),
            title: "Times for Halcyon's second call",
            times: TimesCard(
                purpose: "for Halcyon's recruiter",
                slots: [
                    TimeSlot(start: at(day: 2, 10), end: at(day: 2, 11), note: "WFH"),
                    TimeSlot(start: at(day: 3, 14), end: at(day: 3, 15), note: "WFH"),
                    TimeSlot(start: at(day: 4, 11), end: at(day: 4, 12)),
                ]))

        static let samInvite = DeskCard(
            id: "sam-invite", kind: .invite, at: at(10, 12), title: "Invite: Sam's birthday drinks",
            options: [
                Ask.Option(label: "Accept", acts: true), Ask.Option(label: "Maybe"),
                Ask.Option(label: "Decline"),
            ],
            invite: InviteCard(
                event: CalendarItem(
                    id: "sam-bday", uid: "sam-bday@icloud", title: "Sam's birthday drinks",
                    start: when(day: 5, 19, 30), end: when(day: 5, 23), location: "The Lantern",
                    calendar: kumo, status: .hold)))

        // MARK: Kumo's work

        static let ledger = KumoLedger(
            came: 47,
            needYou: [thanksDraft, halcyonTimes, samInvite],
            handled: [
                DoneEntry(
                    id: "h1", at: at(15, 2), text: "Electricity bill → Admin, due 14 Nov",
                    reason: "A bill with a date on it; a reminder's set for the 12th."),
                DoneEntry(
                    id: "h2", at: at(14, 40), text: "Dentist moved to Fri 13, 9:30",
                    reason: "Bright Smile's mail confirmed the new time.", undo: true),
                DoneEntry(
                    id: "h3", at: at(13, 15), text: "Pizza Planet promos: unsubscribed, binned",
                    reason: "You haven't opened one since March.", undo: true),
                DoneEntry(
                    id: "h4", at: at(11, 30), text: "Climbing with Sam → your calendar, 20:00",
                    reason: "Sam confirmed by mail.", undo: true),
                DoneEntry(
                    id: "h5", at: at(10, 5), text: "Northwind: Priya's reply → Job search",
                    reason: "A reply to your note; nothing to answer yet."),
                DoneEntry(
                    id: "h6", at: at(8, 20), text: "Parcel on Thursday, 14:00–15:00",
                    reason: "You're working from home then."),
            ],
            cleared: (0..<38).map { index in
                let samples = [
                    ("Bank statement", "routine, nothing due"),
                    ("CI passed on ito-core", "you saw it on the PR"),
                    ("Weekly running summary", "nothing new"),
                    ("Water bill", "direct debit, nothing to do"),
                    ("Daily digest", "you rarely open these"),
                    ("Sam: “ha, see you there”", "a reply, no action"),
                ]
                let (text, reason) = samples[index % samples.count]
                return DoneEntry(
                    id: DoneID(rawValue: "c\(index)"), at: at(8 + index % 7, index % 60),
                    text: text, reason: reason, quiet: true)
            },
            trust: [
                KumoLedger.Trust(
                    kind: "Sorting mail", symbol: "tray", step: .trusted,
                    line:
                        "Two weeks without a correction on sorting. I've stopped showing you the cleared ones."
                ),
                KumoLedger.Trust(
                    kind: "Calendar", symbol: "calendar", step: .spotChecks,
                    line:
                        "You fixed the dentist time on Tuesday, so I'm back to showing you about one in five."
                ),
                KumoLedger.Trust(
                    kind: "Drafts", symbol: "envelope", step: .learning,
                    line: "Every draft waits for you. Your casual style is still new to me."),
            ])
    }
#endif
