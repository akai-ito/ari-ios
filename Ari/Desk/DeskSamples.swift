#if DEBUG
    import AriKit
    import Foundation

    /// The Desk on the Thursday of Halcyon, from the milestone's design record, for previews: times are
    /// relative to now, so "Today" stays today.
    enum DeskSamples {
        // MARK: Coming up, for the thread

        static let comingUp: [CalendarItem] = [
            CalendarItem(
                id: "prep", uid: "prep@kumo", title: "Prep: Halcyon technical", start: when(13, 0),
                end: when(14, 0), calendar: kumo, motion: "job-search"),
            CalendarItem(
                id: "halcyon", uid: "halcyon@icloud", title: "Halcyon technical",
                start: when(14, 0), end: when(15, 0), location: "Teams", calendar: home,
                motion: "job-search"),
            CalendarItem(
                id: "mira", uid: "mira@icloud", title: "Dinner with Mira", start: when(19, 30),
                end: when(21, 30), location: "Dishoom Shoreditch", calendar: home,
                leaveAt: at(19, 5)),
            CalendarItem(
                id: "parkrun", uid: "parkrun@icloud", title: "Parkrun", start: when(day: 1, 9, 0),
                end: when(day: 1, 9, 45), location: "Burgess Park", calendar: home),
            CalendarItem(
                id: "hold-mon", uid: "hold-mon@kumo", title: "Hold: Halcyon final",
                start: when(day: 2, 10),
                end: when(day: 2, 11), calendar: kumo, status: .hold),
            CalendarItem(
                id: "florence", uid: "florence@icloud", title: "Florence with Mira",
                start: allDay(7), end: allDay(10), allDay: true, calendar: home,
                motion: "florence"),
        ]

        // MARK: Cards

        static let hotelDraft = DeskCard(
            id: "hotel-orto", kind: .draft, motion: "florence", at: at(7, 2),
            title: "Draft to Hotel Orto",
            options: [Ask.Option(label: "Drop it")],
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

        static let tessDraft = DeskCard(
            id: "tess", kind: .draft, motion: "job-search",
            at: at(day: -1, 18, 4),
            title: "Draft to Tess Harlow",
            options: [Ask.Option(label: "Drop it")],
            draft: DraftCard(
                account: "iCloud", from: "divy@icloud.com", to: ["Tess Harlow"],
                subject: "Halcyon: technical interview slots",
                body:
                    "Hey Tess! Mon 10 or Fri 10 both work my end, whatever's easier for the panel "
                    + ":) CV attached in case they want the latest.",
                messageID: "draft-2c91@divy.icloud.com"))

        static let halcyonTimes = DeskCard(
            id: "halcyon-times", kind: .times, motion: "job-search", at: at(8, 15),
            title: "Times for Halcyon's final round",
            times: TimesCard(
                purpose: "for Tess's draft",
                slots: [
                    TimeSlot(start: at(day: 4, 10), end: at(day: 4, 11), note: "WFH"),
                    TimeSlot(start: at(day: 4, 14), end: at(day: 4, 15), note: "WFH"),
                    TimeSlot(start: at(day: 6, 11), end: at(day: 6, 12)),
                    TimeSlot(start: at(day: 8, 10), end: at(day: 8, 11), note: "WFH"),
                ]))

        static let northwindInvite = DeskCard(
            id: "northwind-invite", kind: .invite, motion: "job-search",
            at: at(12, 58), title: "Invite: Northwind, second round",
            options: [
                Ask.Option(label: "Accept", acts: true), Ask.Option(label: "Maybe"),
                Ask.Option(label: "Decline"),
            ],
            invite: InviteCard(
                event: CalendarItem(
                    id: "northwind", uid: "northwind-2@northwind.example",
                    title: "Freya: Northwind, second round", start: when(day: 5, 16),
                    end: when(day: 5, 17), location: "Zoom", calendar: kumo, status: .hold)))

        static let revolutQuestion = DeskCard(
            id: "revolut", kind: .question, at: at(9, 20),
            title: "Binned “Your account update” from Revolut",
            options: [Ask.Option(label: "Right"), Ask.Option(label: "No, keep it")],
            allowsText: true,
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

        static let allCards = [
            tessDraft, halcyonTimes, northwindInvite, revolutQuestion, outlookOffer, futureCard,
        ]

        static func context(_ card: DeskCard) -> String? {
            switch card.motion {
            case "job-search": "Job search"
            case "florence": "Florence"
            default: nil
            }
        }

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
