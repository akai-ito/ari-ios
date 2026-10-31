#if DEBUG
    import AriKit
    import Foundation

    /// The Desk on the Thursday of QRT, from the milestone's design record, for previews: times are
    /// relative to now, so "Today" stays today.
    enum DeskSamples {
        // MARK: Briefings

        static let morning = Briefing(
            id: "b-morning", kind: .morning, at: at(7, 40),
            lines: [
                BriefingLine(text: "Poppy sent the Teams link for this afternoon; it's on the event."),
                BriefingLine(
                    text:
                        "Hotel Orto confirmed Florence, but you land 22:10 and check-in closes "
                        + "22:00. I drafted a note asking them to wait.",
                    card: "hotel-orto"),
                BriefingLine(text: "Easy 30 minutes or rest today; big afternoon."),
            ],
            handled: 9)

        static let since = Briefing(
            id: "b-since", kind: .since, at: at(13, 10),
            lines: [
                BriefingLine(
                    text: "Katia invited you to Citadel's second round. It's held in my calendar.",
                    card: "citadel-invite")
            ])

        // MARK: Coming up

        static let comingUp: [CalendarItem] = [
            CalendarItem(
                id: "prep", uid: "prep@kumo", title: "Prep: QRT technical", start: when(13, 0),
                end: when(14, 0), calendar: kumo, motion: "job-search"),
            CalendarItem(
                id: "qrt", uid: "qrt@icloud", title: "QRT technical", start: when(14, 0),
                end: when(15, 0), location: "Teams", calendar: home, motion: "job-search"),
            CalendarItem(
                id: "janki", uid: "janki@icloud", title: "Dinner with Janki", start: when(19, 30),
                end: when(21, 30), location: "Dishoom Shoreditch", calendar: home,
                leaveAt: at(19, 5)),
            CalendarItem(
                id: "parkrun", uid: "parkrun@icloud", title: "Parkrun", start: when(day: 1, 9, 0),
                end: when(day: 1, 9, 45), location: "Burgess Park", calendar: home),
            CalendarItem(
                id: "hold-mon", uid: "hold-mon@kumo", title: "Hold: QRT final",
                start: when(day: 2, 10),
                end: when(day: 2, 11), calendar: kumo, status: .hold),
            CalendarItem(
                id: "florence", uid: "florence@icloud", title: "Florence with Janki",
                start: allDay(7), end: allDay(10), allDay: true, calendar: home,
                motion: "florence"),
        ]

        // MARK: Cards

        static let hotelDraft = DeskCard(
            id: "hotel-orto", kind: .draft, motion: "florence", at: at(7, 2),
            title: "Draft to Hotel Orto",
            draft: DraftCard(
                account: "iCloud", from: "divy@icloud.com", to: ["Hotel Orto <info@hotelorto.it>"],
                subject: "Re: Booking confirmed, 12–15 Nov",
                body: """
                    Ciao! We land at 22:10, could you hold the room and leave the key with the \
                    night porter? We should be with you by 23:00.

                    Grazie mille,
                    Divy
                    """,
                messageID: "draft-7f3a91@divy.icloud.com"))

        static let poppyDraft = DeskCard(
            id: "poppy", kind: .draft, motion: "job-search",
            at: at(day: -1, 18, 4),
            title: "Draft to Poppy Walton",
            draft: DraftCard(
                account: "iCloud", from: "divy@icloud.com", to: ["Poppy Walton"],
                subject: "QRT: technical interview slots",
                body:
                    "Hey Poppy! Mon 10 or Fri 10 both work my end, whatever's easier for the panel "
                    + ":) CV attached in case they want the latest.",
                messageID: "draft-2c91@divy.icloud.com"))

        static let qrtTimes = DeskCard(
            id: "qrt-times", kind: .times, motion: "job-search", at: at(8, 15),
            title: "Times for QRT's final round",
            times: TimesCard(
                purpose: "for Poppy's draft",
                slots: [
                    TimeSlot(start: at(day: 4, 10), end: at(day: 4, 11), note: "WFH"),
                    TimeSlot(start: at(day: 4, 14), end: at(day: 4, 15), note: "WFH"),
                    TimeSlot(start: at(day: 6, 11), end: at(day: 6, 12)),
                    TimeSlot(start: at(day: 8, 10), end: at(day: 8, 11), note: "WFH"),
                ]))

        static let citadelInvite = DeskCard(
            id: "citadel-invite", kind: .invite, motion: "job-search",
            at: at(12, 58), title: "Invite: Citadel, second round",
            options: [
                Ask.Option(label: "Accept", acts: true), Ask.Option(label: "Maybe"),
                Ask.Option(label: "Decline"),
            ],
            invite: InviteCard(
                event: CalendarItem(
                    id: "citadel", uid: "citadel-2@citadel.com",
                    title: "Katia: Citadel, second round", start: when(day: 5, 16),
                    end: when(day: 5, 17), location: "Zoom", calendar: kumo, status: .hold)))

        static let revolutQuestion = DeskCard(
            id: "revolut", kind: .question, at: at(9, 20),
            title: "Binned “Your account update” from Revolut",
            options: [Ask.Option(label: "Right"), Ask.Option(label: "No, keep it")], allowsText: true,
            question: QuestionCard(text: "I binned “Your account update” from Revolut. Right?"))

        static let outlookOffer = DeskCard(
            id: "outlook", kind: .offer, at: at(day: -2, 20, 0), title: "Watch your Outlook too",
            options: [Ask.Option(label: "Connect", acts: true), Ask.Option(label: "Not now")],
            offer: OfferCard(
                text: "Want me to watch your Outlook too? Your recruiters write to it.",
                capability: "mail"))

        static let futureCard = DeskCard(
            id: "future", kind: CardKind(rawValue: "parcel"), at: at(10, 0),
            title: "Your DPD parcel arrives between 14:00 and 15:00")

        static let waiting = [hotelDraft, revolutQuestion, citadelInvite, qrtTimes, futureCard]
        static let allCards = [
            poppyDraft, qrtTimes, citadelInvite, revolutQuestion, outlookOffer, futureCard,
        ]

        static func context(_ card: DeskCard) -> String? {
            switch card.motion {
            case "job-search": "Job search"
            case "florence": "Florence"
            default: nil
            }
        }

        // MARK: Done

        static let donePage = DonePage(
            entries: [
                DoneEntry(
                    id: "d1", at: at(9, 14), text: "Domino's: unsubscribed, binned", undo: true),
                DoneEntry(
                    id: "q1", at: at(9, 10), text: "Monzo statement",
                    reason: "routine, nothing due",
                    quiet: true),
                DoneEntry(
                    id: "d2", at: at(9, 2),
                    text: "Hotel Orto booking → Florence › Stay, on your calendar"),
                DoneEntry(
                    id: "q2", at: at(8, 51), text: "GitHub: CI passed on ito-core",
                    reason: "you saw it on the PR", quiet: true),
                DoneEntry(
                    id: "d3", at: at(8, 40), text: "Council tax: due 1 Dec, reminder on the 24th"),
                DoneEntry(
                    id: "q3", at: at(8, 12), text: "Poppy: “thanks!”",
                    reason: "a thank-you, no action", quiet: true),
                DoneEntry(
                    id: "q4", at: at(7, 3), text: "Medium Daily", reason: "you rarely open these",
                    quiet: true),
                DoneEntry(
                    id: "d4", at: at(day: -1, 18, 20),
                    text: "Dentist moved to Fri 13, 9:30; calendar updated"),
                DoneEntry(
                    id: "d5", at: at(day: -1, 11, 5), text: "Uber Eats promo: unsubscribed, binned",
                    undo: true),
                DoneEntry(
                    id: "q5", at: at(day: -1, 9, 30), text: "Thames Water bill",
                    reason: "direct debit, nothing to do", quiet: true),
            ],
            hasMore: true)

        static let olderDone = [
            DoneEntry(
                id: "d6", at: at(day: -3, 16, 40),
                text: "Citadel: Katia's reply → Job search, waiting on them"),
            DoneEntry(
                id: "q6", at: at(day: -3, 8, 0), text: "Strava weekly summary",
                reason: "nothing new", quiet: true),
        ]

        // MARK: Making times

        private static let home = CalendarName(name: "Home")
        private static let kumo = CalendarName(name: "Kumo", kumo: true)

        /// A time on a day relative to today, in this device's zone.
        static func at(day: Int = 0, _ hour: Int, _ minute: Int = 0) -> Timestamp {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: .now)
            let date = calendar.date(
                byAdding: DateComponents(day: day, hour: hour, minute: minute), to: start)!
            return Timestamp(date.formatted(.iso8601))!
        }

        /// A calendar time on a day relative to today, in this device's zone.
        static func when(day: Int = 0, _ hour: Int, _ minute: Int = 0) -> When {
            When(at(day: day, hour, minute).date)
        }

        /// An all-day day relative to today.
        static func allDay(_ day: Int) -> When {
            let calendar = Calendar.current
            let date = calendar.date(byAdding: .day, value: day, to: .now)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return When(year: parts.year!, month: parts.month!, day: parts.day!)
        }

    }
#endif
