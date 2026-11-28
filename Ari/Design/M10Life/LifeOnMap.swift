#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Structure 2: Life on a map

    enum S2Range: Int { case today, week, month, year }

    enum S2Sheet {
        case today
        case summary(title: String, line: String, extra: String?)
        case place
        case journal
    }

    extension LifeData {
        static let toOrrins: [CLLocationCoordinate2D] = [
            (55.9362, -3.1925), (55.9372, -3.2010), (55.9420, -3.2040), (55.9475, -3.2060),
            (55.9530, -3.2060), (55.9585, -3.2090),
        ].map { .init(latitude: $0.0, longitude: $0.1) }
        static let toLeo: [CLLocationCoordinate2D] = [
            (55.9530, -3.2000), (55.9560, -3.1880), (55.9625, -3.1795), (55.9680, -3.1720),
            (55.9712, -3.1655),
        ].map { .init(latitude: $0.0, longitude: $0.1) }
        static let toGym: [CLLocationCoordinate2D] = [
            (55.9530, -3.2000), (55.9545, -3.1945), (55.9563, -3.1880), (55.9604, -3.1820),
            (55.9625, -3.1795),
        ].map { .init(latitude: $0.0, longitude: $0.1) }

        static func around(_ route: [CLLocationCoordinate2D], pad: Double = 1.3)
            -> MKCoordinateRegion
        {
            let lats = route.map(\.latitude)
            let lons = route.map(\.longitude)
            let la = (lats.min()! + lats.max()!) / 2
            let lo = (lons.min()! + lons.max()!) / 2
            let span = max((lats.max()! - lats.min()!) * 1.8, lons.max()! - lons.min()!) * pad
            return MKCoordinateRegion(
                center: .init(latitude: la, longitude: lo),
                span: .init(latitudeDelta: span / 1.8, longitudeDelta: span))
        }
    }

    struct S2Map: View {
        let range: S2Range
        var look: MapLook = .muted
        let sheet: S2Sheet

        var body: some View {
            ZStack(alignment: .top) {
                LifeMap(
                    scene: scene, look: look, step: 5, zoom: range == .year ? 6 : 15, credit: false
                )
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.ariBackground.opacity(0.85), .clear], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
                ZoomScale(levels: ["Today", "Week", "Month", "Year"], current: range.rawValue)
                    .padding(.top, 6)
                RestingSheet(height: sheetHeight) { sheetContent }
                    .padding(.bottom, 0)
            }
            .background(Color.ariBackground)
        }

        private var sheetHeight: CGFloat {
            switch sheet {
            case .today: 340
            case .summary: 290
            case .place: 420
            case .journal: 720
            }
        }

        private var scene: MapScene {
            switch range {
            case .today:
                var scene = MapScene.today()
                scene.region = MKCoordinateRegion(
                    center: .init(latitude: 55.9490, longitude: -3.1880),
                    span: .init(latitudeDelta: 0.03, longitudeDelta: 0.062))
                scene.heat = LifeData.heat(LifeData.week, includingHome: false).map {
                    HeatPoint(coordinate: $0.coordinate, weight: $0.weight * 0.5)
                }
                scene.spread = 22
                scene.faintTrails = [
                    [LifeData.office.coordinate, LifeData.meadows.coordinate]
                ]
                scene.kumoSize = 46
                return scene
            case .week, .month:
                let selected = isPlace
                return MapScene(
                    region: MKCoordinateRegion(
                        center: .init(latitude: selected ? 55.9440 : 55.9480, longitude: -3.1880),
                        span: .init(latitudeDelta: 0.03, longitudeDelta: 0.062)),
                    heat: LifeData.heat(
                        range == .week ? LifeData.week : LifeData.month, includingHome: false),
                    spread: 20,
                    labels: [
                        LifeData.office, LifeData.gym, LifeData.home, LifeData.leo, LifeData.cafe,
                    ].map {
                        MapLabel(
                            text: $0.name, coordinate: $0.coordinate,
                            strong: selected && $0.id == "gym")
                    },
                    kumo: selected ? nil : LifeData.office.coordinate, kumoSize: 38,
                    kumoMood: .calm,
                    selected: selected ? LifeData.gym.coordinate : nil)
            case .year:
                return MapScene(
                    region: MKCoordinateRegion(
                        center: .init(latitude: 43.6, longitude: -5),
                        span: .init(latitudeDelta: 20, longitudeDelta: 28)),
                    heat: LifeData.yearHeat, spread: 30,
                    labels: [
                        MapLabel(
                            text: "Lisbon · 6 days",
                            coordinate: .init(latitude: 38.72, longitude: -9.14)),
                        MapLabel(
                            text: "London · 9 days",
                            coordinate: .init(latitude: 51.51, longitude: -0.13)),
                        MapLabel(
                            text: "Skye · 4 days",
                            coordinate: .init(latitude: 57.27, longitude: -6.22), below: false),
                        MapLabel(
                            text: "Glasgow · 3 days",
                            coordinate: .init(latitude: 55.86, longitude: -4.25)),
                        MapLabel(
                            text: "Home", coordinate: .init(latitude: 55.95, longitude: -3.19),
                            below: false, strong: true),
                    ])
            }
        }

        private var isPlace: Bool { if case .place = sheet { true } else { false } }

        @ViewBuilder
        private var sheetContent: some View {
            switch sheet {
            case .today: todaySheet
            case .summary(let title, let line, let extra): summarySheet(title, line, extra)
            case .place: placeSheet
            case .journal: journalSheet
            }
        }

        private func sheetTabs(_ current: Int) -> some View {
            HStack(spacing: 16) {
                ForEach(
                    Array(["Today", "Journal", "Places", "Going on"].enumerated()), id: \.offset
                ) { i, word in
                    Text(word)
                        .font(i == current ? .ariHeading : .subheadline)
                        .foregroundStyle(i == current ? Color.ariText : .ariTertiary)
                }
            }
        }

        private var todaySheet: some View {
            VStack(alignment: .leading, spacing: 18) {
                sheetTabs(0)
                KumoSays(
                    mood: .proud,
                    text:
                        "Four stops so far, 6.2 km. The run with Leo is at 5:30, from the Meadows.",
                    size: 34)
                ScrollView(.horizontal) { TrailStrip() }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -20)
                    .contentMargins(.horizontal, 20)
            }
        }

        private func summarySheet(_ title: String, _ line: String, _ extra: String?) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.ariHeading).foregroundStyle(.ariText)
                Text(line)
                    .font(.ariBody)
                    .foregroundStyle(.ariSecondary)
                    .lineSpacing(3)
                if let extra {
                    HStack(spacing: 10) {
                        DotGlyph(symbol: "questionmark", side: 30)
                        Text(extra).font(.subheadline).foregroundStyle(.ariText)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(
                            .ariTertiary)
                    }
                    .padding(10)
                    .background(
                        Color.ariField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }

        private var placeSheet: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    DotGlyph(symbol: "dumbbell.fill", side: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The gym").font(.ariHeading).foregroundStyle(.ariText)
                        Text("My name for it · Apple calls it Forgeworks, Leith Walk")
                            .font(.caption).foregroundStyle(.ariTertiary)
                    }
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ariSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.ariField, in: Circle())
                }
                Text("6 h this week · 4 visits · usually 07:00, for 45 minutes")
                    .font(.subheadline).foregroundStyle(.ariSecondary)
                WeekDots(visited: [0, 2, 3, 5], today: 1)
                Text("Four times this week, the most since September. Thursday's was the longest.")
                    .font(.ariBody).foregroundStyle(.ariText).lineSpacing(3)
                HStack(spacing: 8) {
                    Chip(text: "Rename")
                    Chip(text: "Every visit")
                    Chip(text: "Not a place")
                }
            }
        }

        private var journalSheet: some View {
            VStack(alignment: .leading, spacing: 18) {
                sheetTabs(1)
                ForEach(Array(JournalEntry.week.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.day).font(.caption.weight(.semibold)).foregroundStyle(
                                .ariTertiary)
                            Text(entry.text)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.ariText)
                                .lineSpacing(2)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        LifeMap(
                            scene: MapScene(
                                region: LifeData.around(entry.route), trails: [entry.route],
                                stops: [entry.route.last!]),
                            look: .halftone, step: 3.2, credit: false
                        )
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.ariLine, lineWidth: 0.5)
                        }
                    }
                    Rectangle().fill(Color.ariLine.opacity(0.6)).frame(height: 0.5)
                }
            }
        }
    }

    struct JournalEntry {
        let day: String
        let text: String
        let route: [CLLocationCoordinate2D]

        static let week: [JournalEntry] = [
            JournalEntry(
                day: "Saturday 21",
                text:
                    "Up the hill with Mira before the rain. We made the top just as it started, and ran the last bit down.",
                route: LifeData.hillWalk),
            JournalEntry(
                day: "Friday 20",
                text:
                    "Worked from home all day. Dinner at Orrin's with Omar; the fig thing was the best I've had all month.",
                route: LifeData.toOrrins),
            JournalEntry(
                day: "Thursday 19",
                text: "Leo cooked. We stayed up too late planning Lisbon and didn't book anything.",
                route: LifeData.toLeo),
            JournalEntry(
                day: "Wednesday 18",
                text: "Gym after the office. The new deadlift felt fine, which surprised me.",
                route: LifeData.toGym),
        ]
    }

    /// Mon–Sun with a lit dot on the days you went.
    struct WeekDots: View {
        let visited: Set<Int>
        let today: Int

        var body: some View {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(visited.contains(i) ? Color.ariBone : Color.ariLine)
                            .frame(width: 9, height: 9)
                        Text(["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"][i])
                            .font(.caption2)
                            .foregroundStyle(i == 6 ? Color.ariText : .ariTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Today's trail sideways: each place a small block, the way between them dotted.
    struct TrailStrip: View {
        static let blocks: [(String, String, String, Bool, Bool)] = [
            ("08:10", "The café", "50 min", false, false),
            ("09:20", "The office", "4 h 05", false, false),
            ("13:50", "Northwind", "1 h 20", false, false),
            ("15:40", "The office", "now", true, false),
            ("17:30", "Run with Leo", "the Meadows", false, true),
        ]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(Self.blocks.enumerated()), id: \.offset) { i, block in
                    if i > 0 {
                        Canvas { context, size in
                            var path = Path()
                            var x: CGFloat = 2
                            while x < size.width {
                                path.addEllipse(
                                    in: CGRect(
                                        x: x - 1, y: size.height / 2 - 1, width: 2, height: 2))
                                x += block.4 ? 7 : 4
                            }
                            context.fill(
                                path,
                                with: .color(
                                    block.4 ? .ariTertiary.opacity(0.5) : .ariSecondary.opacity(0.7)
                                ))
                        }
                        .frame(width: 16, height: 10)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.0).font(.caption2.monospacedDigit()).foregroundStyle(
                            .ariTertiary)
                        Text(block.1)
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(block.4 ? Color.ariTertiary : .ariText)
                            .lineLimit(1)
                        Text(block.2)
                            .font(.caption2)
                            .foregroundStyle(block.3 ? Color.ariText : .ariTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 92, alignment: .leading)
                    .background(
                        block.4 ? Color.clear : Color.ariField,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                block.3 ? Color.ariBone : (block.4 ? Color.ariLine : .clear),
                                lineWidth: 1)
                    }
                }
            }
            .fixedSize()
        }
    }
#endif
