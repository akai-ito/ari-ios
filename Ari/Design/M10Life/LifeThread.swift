#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Structure 3: one thread back, with look-up on top

    /// The look-up field at the top of Life: type or speak; Kumo answers from your life.
    struct LookUpField: View {
        var text: String?

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.ariTertiary)
                Text(text ?? "Look anything up, or ask")
                    .foregroundStyle(text == nil ? Color.ariTertiary : .ariText)
                Spacer()
                Image(systemName: text == nil ? "mic" : "xmark.circle.fill")
                    .foregroundStyle(.ariTertiary)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Color.ariField, in: Capsule())
        }
    }

    /// What's still going, as short threads you can pull: a word each.
    struct StillGoing: View {
        static let items: [(String, String, Bool)] = [
            ("Northwind", "final today", true), ("Spring 10k", "week 4", false),
            ("Lisbon", "flights held", false), ("Mira's birthday", "Friday week", false),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                SectionHead(text: "Still going")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(Self.items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                DotRun(lit: item.2).frame(width: 22, height: 6)
                                Text(item.0).font(.subheadline.weight(.semibold)).foregroundStyle(
                                    .ariText)
                                Text(item.1).font(.caption).foregroundStyle(
                                    item.2 ? Color.ariText : .ariTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.ariSurface, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    struct DotRun: View {
        var lit = false
        var body: some View {
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = 1
                while x < size.width - 4 {
                    path.addEllipse(
                        in: CGRect(x: x - 1, y: size.height / 2 - 1, width: 2, height: 2))
                    x += 4
                }
                context.fill(path, with: .color(.ariSecondary))
                let r: CGFloat = 3
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: size.width - 2 * r, y: size.height / 2 - r, width: 2 * r,
                            height: 2 * r)),
                    with: .color(lit ? .ariText : .ariSecondary))
            }
        }
    }

    /// One stretch of the telescoping thread: the further back, the sparser the dots and the
    /// fewer the words.
    struct BackRow: Identifiable {
        enum Kind { case now, day, span, chapter, month }
        var id: String { title }
        let kind: Kind
        let title: String
        let line: String
        var route: [CLLocationCoordinate2D]?
        var heat: [LifeData.Spot]?
        var symbol: String?
    }

    struct BackThread: View {
        let rows: [BackRow]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        BackSegment(kind: row.kind).frame(width: 18)
                        content(row)
                            .padding(.bottom, gap(row.kind))
                    }
                }
            }
        }

        private func gap(_ kind: BackRow.Kind) -> CGFloat {
            switch kind {
            case .now, .day: 20
            case .span, .month: 24
            case .chapter: 16
            }
        }

        @ViewBuilder
        private func content(_ row: BackRow) -> some View {
            switch row.kind {
            case .chapter:
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.ariHeading).foregroundStyle(.ariText)
                    Text(row.line).font(.footnote).foregroundStyle(.ariTertiary)
                }
                .padding(.top, 2)
            default:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.kind == .now ? Color.ariText : .ariTertiary)
                        Text(row.line)
                            .font(
                                row.kind == .day || row.kind == .now
                                    ? .ariBody : .system(.subheadline, design: .serif)
                            )
                            .foregroundStyle(row.kind == .month ? Color.ariSecondary : .ariText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let route = row.route {
                        LifeMap(
                            scene: MapScene(
                                region: LifeData.around(route), trails: [route],
                                stops: [route.last!]),
                            look: .halftone, step: 3.2, credit: false
                        )
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.ariLine, lineWidth: 0.5)
                        }
                    } else if let heat = row.heat {
                        LifeMap(
                            scene: .spots(heat, region: LifeData.city, spread: 5),
                            look: .halftone, step: 3, credit: false
                        )
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.ariLine, lineWidth: 0.5)
                        }
                    } else if let symbol = row.symbol {
                        DotGlyph(symbol: symbol, side: 44).frame(width: 64)
                    }
                }
            }
        }
    }

    struct BackSegment: View {
        let kind: BackRow.Kind

        var body: some View {
            Canvas { context, size in
                let x = size.width / 2
                let spacing: CGFloat =
                    switch kind {
                    case .now, .day: 4
                    case .span: 6
                    case .month: 8
                    case .chapter: 10
                    }
                var path = Path()
                var y: CGFloat = 0
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    y += spacing
                }
                context.fill(
                    path, with: .color(.ariSecondary.opacity(kind == .chapter ? 0.4 : 0.65)))
                switch kind {
                case .now:
                    let ring = CGRect(x: x - 6, y: 4, width: 12, height: 12)
                    context.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
                    context.stroke(
                        Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText),
                        lineWidth: 1.3)
                    context.fill(
                        Path(ellipseIn: ring.insetBy(dx: 3.8, dy: 3.8)), with: .color(.ariText))
                case .day, .month:
                    let r: CGFloat = kind == .day ? 3.2 : 2.6
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: 8 - r, width: 2 * r, height: 2 * r)),
                        with: .color(.ariSecondary))
                case .span:
                    var knot = Path()
                    for dy in stride(from: 4.0, through: 24.0, by: 4.6) {
                        knot.addEllipse(
                            in: CGRect(x: x - 2.4, y: dy - 2.4, width: 4.8, height: 4.8))
                    }
                    context.fill(knot, with: .color(.ariSecondary))
                case .chapter:
                    let rect = CGRect(x: x - 5, y: 6, width: 10, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.ariBone))
                }
            }
        }
    }

    struct S3Life: View {
        static let rows: [BackRow] = [
            BackRow(
                kind: .now, title: "TODAY, SO FAR",
                line: "The café, the office, Northwind. 6.2 km.",
                route: LifeData.cafeToOffice + LifeData.officeToNorthwind),
            BackRow(
                kind: .day, title: "YESTERDAY", line: "The office, the gym, an early night.",
                route: LifeData.toGym),
            BackRow(kind: .day, title: "SUNDAY", line: "A short run, then nothing at all."),
            BackRow(
                kind: .day, title: "SATURDAY", line: "Up the hill with Mira before the rain.",
                route: LifeData.hillWalk),
            BackRow(
                kind: .day, title: "FRIDAY", line: "Dinner at Orrin's with Omar.",
                route: LifeData.toOrrins),
            BackRow(
                kind: .span, title: "LAST WEEK",
                line: "Mostly the office. Leo's on Thursday, and two hours in Dalry I can't place.",
                heat: LifeData.week),
            BackRow(
                kind: .span, title: "EARLIER IN NOVEMBER",
                line: "The boiler, the second Northwind call, Mira's ceramics idea.",
                heat: LifeData.month),
            BackRow(
                kind: .chapter, title: "The Northwind autumn", line: "September to now · 3 months"),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LookUpField()
                    StillGoing()
                    BackThread(rows: Self.rows)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    /// Further back: months fold into chapters, trips stay as loops with their maps.
    struct S3Past: View {
        static let rows: [BackRow] = [
            BackRow(
                kind: .chapter, title: "The Northwind autumn", line: "September to now · 3 months"),
            BackRow(
                kind: .month, title: "OCTOBER",
                line: "The first Northwind call. Glasgow for two days with Leo.",
                symbol: "briefcase.fill"),
            BackRow(
                kind: .month, title: "SEPTEMBER",
                line: "My first 10k: 54 minutes, and I nearly cried.", symbol: "figure.run"),
            BackRow(kind: .chapter, title: "The long summer", line: "July and August"),
            BackRow(
                kind: .month, title: "AUGUST",
                line: "Skye, four days, rain every one of them. Worth it.",
                symbol: "mountain.2.fill"),
            BackRow(
                kind: .month, title: "JULY", line: "Nothing to report, beautifully.",
                symbol: "sun.max.fill"),
            BackRow(kind: .chapter, title: "Leaving, then Lisbon", line: "April to June"),
            BackRow(
                kind: .month, title: "JUNE", line: "Leo's 30th, on the roof.",
                symbol: "party.popper.fill"),
            BackRow(
                kind: .month, title: "MAY", line: "Lisbon, six days. Omar came for two.",
                symbol: "airplane"),
            BackRow(
                kind: .month, title: "APRIL", line: "My last day at the old job.",
                symbol: "door.left.hand.open"),
            BackRow(kind: .chapter, title: "Winter at the old job", line: "January to March"),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LookUpField()
                    BackThread(rows: Self.rows)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    /// Looked up: Kumo answers first, then where it sits on your thread, then the pages.
    struct S3LookUp: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LookUpField(text: "dinner with Omar")
                    KumoSays(
                        mood: .bright,
                        text:
                            "Orrin's, in Stockbridge, last Friday from 19:40 to 22:10. You wrote that the fig thing was the best you'd had all month.",
                        size: 36)
                    MapCard(
                        scene: MapScene(
                            region: LifeData.around(LifeData.toOrrins, pad: 1.5),
                            trails: [LifeData.toOrrins], stops: [LifeData.orrins.coordinate],
                            labels: [
                                MapLabel(
                                    text: "Orrin's · Fri 19:40",
                                    coordinate: LifeData.orrins.coordinate, strong: true),
                                MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                            ]),
                        height: 170)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHead(text: "On your thread")
                        ForEach(
                            Array(
                                [
                                    ("Fri 20 Nov", "Orrin's, with Omar"),
                                    ("Sat 3 Oct", "Orrin's again, with Omar and Leo"),
                                    ("May", "Lisbon: Omar came for two days"),
                                ].enumerated()), id: \.offset
                        ) { _, hit in
                            HStack(spacing: 12) {
                                DotRun().frame(width: 22, height: 6)
                                Text(hit.0).font(.caption.monospacedDigit()).foregroundStyle(
                                    .ariTertiary
                                )
                                .frame(width: 70, alignment: .leading)
                                Text(hit.1).font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(.ariText)
                                Spacer()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHead(text: "Pages")
                        PageLine(
                            symbol: "person.fill", title: "Omar",
                            detail: "A friend · last seen Friday")
                        PageLine(
                            symbol: "fork.knife", title: "Orrin's",
                            detail: "A place · 3 visits · Stockbridge")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    struct PageLine: View {
        let symbol: String
        let title: String
        let detail: String

        var body: some View {
            HStack(spacing: 12) {
                DotGlyph(symbol: symbol, side: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ariName).foregroundStyle(.ariText)
                    Text(detail).font(.caption).foregroundStyle(.ariTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }

    // MARK: - A day's page from the journal, with its map

    struct JournalDay: View {
        var look: MapLook = .halftone

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Life")
                    }
                    .font(.body)
                    .foregroundStyle(.ariSecondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saturday").font(.ariTitle).foregroundStyle(.ariText)
                        Text("21 November · 9.4 km · 3 h 10").font(.footnote).foregroundStyle(
                            .ariTertiary)
                    }
                    MapCard(
                        scene: MapScene(
                            region: LifeData.hillRegion, trails: [LifeData.hillWalk],
                            stops: [
                                LifeData.hill.coordinate,
                                CLLocationCoordinate2D(latitude: 55.9476, longitude: -3.1952),
                            ],
                            labels: [
                                MapLabel(
                                    text: "The top · 11:40", coordinate: LifeData.hill.coordinate,
                                    below: false),
                                MapLabel(
                                    text: "The bakery · 13:05",
                                    coordinate: .init(latitude: 55.9476, longitude: -3.1952),
                                    below: false),
                                MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                            ]),
                        look: look, height: 250, step: 4.5)
                    VStack(alignment: .leading, spacing: Rhythm.ariParagraphGap) {
                        Text(
                            "Up the hill with Mira before the rain. We made the top just as it started, and ran the last bit down laughing like idiots."
                        )
                        Text(
                            "Coffee after at the bakery with the blue door off the Grassmarket. I want to go back on a weekday, when it's quiet, and read there."
                        )
                        Text("Mira's going to ask about the ceramics class. I didn't say anything.")
                    }
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(Rhythm.ariLineSpacing)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead(text: "In this day")
                        HStack(spacing: 8) {
                            Chip(text: "The hill")
                            Chip(text: "The bakery · new")
                            Chip(text: "Mira")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    // MARK: - The Desk's day page, where today's trail lives in structure 3

    struct DeskWithDay: View {
        var body: some View {
            ZStack {
                VStack(spacing: 22) {
                    Spacer().frame(height: 70)
                    KumoFace(mood: .proud, size: 100, still: true)
                    Text("That's the hard one done, and done well.")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.ariText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color.ariBackground)
                Color.black.opacity(0.4).ignoresSafeArea()
                RestingSheet(height: 610) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your day").font(.ariHeading).foregroundStyle(.ariText)
                                Text("Tuesday 24 November · 4 places · 6.2 km")
                                    .font(.footnote).foregroundStyle(.ariTertiary)
                            }
                            MapCard(scene: .today(), height: 170)
                            TrailColumn(rows: Array(TrailColumn.today.dropFirst(2)))
                        }
                        .padding(.bottom, 100)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }
#endif
