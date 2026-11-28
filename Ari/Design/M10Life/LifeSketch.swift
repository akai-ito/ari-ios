#if DEBUG
    import SwiftUI

    /// Stills for Milestone 10's first design round: three structures for Ito's life part (Life by
    /// time, Life on a map, and a thread with look-up on top), and the places pieces in them.
    /// `ARI_SKETCH=<name>` opens one from samples, without a server. Everyone and everything in
    /// them is made up; the streets are a real city's, the places in them aren't anyone's.
    enum LifeSketch: String, CaseIterable {
        // Structure 1: Life, one tab, by time.
        case s1Day = "s1-day"
        case s1DayHalftone = "s1-day-halftone"
        case s1Week = "s1-week"
        case s1Year = "s1-year"
        case s1GoingOn = "s1-going-on"
        case s1Places = "s1-places"
        case s1PlacesMuted = "s1-places-muted"
        // Structure 2: Life on a map.
        case s2Today = "s2-today"
        case s2TodayHalftone = "s2-today-halftone"
        case s2Week = "s2-week"
        case s2Month = "s2-month-halftone"
        case s2Year = "s2-year-halftone"
        case s2YearMuted = "s2-year-muted"
        case s2Place = "s2-place"
        case s2Journal = "s2-journal"
        // Structure 3: one thread back, with look-up on top.
        case s3Life = "s3-life"
        case s3Past = "s3-past"
        case s3LookUp = "s3-look-up"
        case s3Day = "s3-journal-day-halftone"
        case s3DayMuted = "s3-journal-day-muted"
        case s3DeskDay = "s3-desk-day"
        // Places pieces.
        case naming = "p-naming"
        case namingNext = "p-naming-next"
        case firstRun = "p-first-run"
        case firstRunAlways = "p-first-run-always"
        // Round 2: Desk · Chat · Life, with Life by time and the lit map for longer stretches.
        case r2Day = "r2-day"
        case r2Week = "r2-week"
        case r2Month = "r2-month"
        case r2Year = "r2-year"
        case r2Search = "r2-search"
        case r2Places = "r2-places"
        case r2Place = "r2-place"
        case r2People = "r2-people"
        case r2PeopleOrder = "r2-people-order"
        case r2Orbits = "r2-people-orbits"
        case r2Person = "r2-person"
        case r2PersonCard = "r2-person-card"
        case r2Linking = "r2-people-link"
        case r2GoingOn = "r2-going-on"
        case r2Made = "r2-made"
        case r2DeskKnows = "r2-desk-knows"
    }

    struct LifeRoot: View {
        let sketch: LifeSketch

        var body: some View {
            Group {
                switch sketch {
                case .s1Day: LifeTabs { S1Day() }
                case .s1DayHalftone: LifeTabs { S1Day(look: .halftone) }
                case .s1Week: LifeTabs { S1Week() }
                case .s1Year: LifeTabs { S1Year() }
                case .s1GoingOn: LifeTabs { S1GoingOn() }
                case .s1Places: LifeTabs { S1Places() }
                case .s1PlacesMuted: LifeTabs { S1Places(look: .muted) }
                case .s2Today: LifeTabs(symbol: "map") { S2Map(range: .today, sheet: .today) }
                case .s2TodayHalftone:
                    LifeTabs(symbol: "map") { S2Map(range: .today, look: .halftone, sheet: .today) }
                case .s2Week:
                    LifeTabs(symbol: "map") {
                        S2Map(
                            range: .week,
                            sheet: .summary(
                                title: "This week",
                                line:
                                    "31 hours at the office, 6 at the gym, 4 at Leo's. More gym than last week, less café.",
                                extra: nil))
                    }
                case .s2Month:
                    LifeTabs(symbol: "map") {
                        S2Map(
                            range: .month, look: .halftone,
                            sheet: .summary(
                                title: "November",
                                line:
                                    "Mostly the office and the gym. Two new places; one I can't name yet.",
                                extra: "Dalry, last Tuesday · what was it?"))
                    }
                case .s2Year:
                    LifeTabs(symbol: "map") {
                        S2Map(
                            range: .year, look: .halftone,
                            sheet: .summary(
                                title: "2026 so far",
                                line:
                                    "Home most of the year. Lisbon in May, Skye in August, London three times.",
                                extra: nil))
                    }
                case .s2YearMuted:
                    LifeTabs(symbol: "map") {
                        S2Map(
                            range: .year,
                            sheet: .summary(
                                title: "2026 so far",
                                line:
                                    "Home most of the year. Lisbon in May, Skye in August, London three times.",
                                extra: nil))
                    }
                case .s2Place: LifeTabs(symbol: "map") { S2Map(range: .week, sheet: .place) }
                case .s2Journal: LifeTabs(symbol: "map") { S2Map(range: .today, sheet: .journal) }
                case .s3Life: LifeTabs { S3Life() }
                case .s3Past: LifeTabs { S3Past() }
                case .s3LookUp: LifeTabs { S3LookUp() }
                case .s3Day: LifeTabs { JournalDay() }
                case .s3DayMuted: LifeTabs { JournalDay(look: .muted) }
                case .s3DeskDay:
                    LifeTabs(selected: .desk, desk: { DeskWithDay() }) { Color.ariBackground }
                case .naming: KnowYouPlaces()
                case .namingNext: KnowYouPlaces(second: true)
                case .firstRun: FirstRunLocation()
                case .firstRunAlways: FirstRunAlways()
                case .r2Day: LifeTabs { R2Day() }
                case .r2Week: LifeTabs { R2Week() }
                case .r2Month: LifeTabs { R2Month() }
                case .r2Year: LifeTabs { R2Year() }
                case .r2Search: LifeTabs { R2Search() }
                case .r2Places: LifeTabs { R2Places() }
                case .r2Place: LifeTabs { R2Place() }
                case .r2People: LifeTabs { R2People() }
                case .r2PeopleOrder: LifeTabs { R2PeopleOrder() }
                case .r2Orbits: LifeTabs { R2Orbits() }
                case .r2Person: LifeTabs { R2Person() }
                case .r2PersonCard: LifeTabs { R2PersonCard() }
                case .r2Linking: R2Linking()
                case .r2GoingOn: LifeTabs { R2GoingOn() }
                case .r2Made: LifeTabs { R2Made() }
                case .r2DeskKnows: R2DeskKnows()
                }
            }
            .tint(.ariText)
        }
    }

    // MARK: - Tabs

    enum LifeTab: Hashable { case desk, chat, life }

    /// Desk · Chat · Life, with Life up (or the Desk).
    struct LifeTabs<Desk: View, Life: View>: View {
        var symbol = "point.bottomleft.forward.to.point.topright.scurvepath"
        var selected = LifeTab.life
        @ViewBuilder var desk: Desk
        @ViewBuilder var life: Life

        var body: some View {
            TabView(selection: .constant(selected)) {
                Tab("Desk", systemImage: "rectangle.grid.1x2", value: .desk) { desk }
                Tab("Chat", systemImage: "bubble.left", value: .chat) { Color.ariBackground }
                Tab("Life", systemImage: symbol, value: .life) { life }
            }
        }
    }

    extension LifeTabs where Desk == Color {
        init(
            symbol: String = "point.bottomleft.forward.to.point.topright.scurvepath",
            @ViewBuilder life: () -> Life
        ) {
            self.init(symbol: symbol, selected: .life, desk: { Color.ariBackground }, life: life)
        }
    }

    /// A label that tells a variant apart.
    struct LifeVariantLabel: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.ariBackground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ariBone, in: Capsule())
        }
    }
#endif
