#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Structure 1: Life, one tab, by time

    /// The lenses of Life in structure 1.
    enum S1Lens: Int { case days, places, people, goingOn, pages }

    struct S1Page<Content: View>: View {
        let lens: S1Lens
        @ViewBuilder var content: Content

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LensRow(
                        lenses: ["Days", "Places", "People", "Going on", "Pages"],
                        current: lens.rawValue)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    struct ZoomHeader: View {
        let title: String
        let subtitle: String
        let zoom: Int
        var levels = ["Day", "Week", "Month", "Year"]

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.ariTitle).foregroundStyle(.ariText)
                HStack {
                    Text(subtitle).font(.footnote).foregroundStyle(.ariTertiary)
                    Spacer()
                    ZoomScale(levels: levels, current: zoom)
                }
            }
        }
    }

    /// Days, zoomed in on today: the route on a small map, then the day's thread with each place
    /// as a quiet block.
    struct S1Day: View {
        var look: MapLook = .muted

        var body: some View {
            S1Page(lens: .days) {
                ZoomHeader(title: "Tuesday", subtitle: "24 November · 4 places · 6.2 km", zoom: 0)
                MapCard(scene: .today(), look: look, height: 200)
                KumoSays(
                    mood: .proud,
                    text:
                        "The final's behind you. I kept the day as you went; I'll write it up tonight.",
                    size: 34)
                TrailColumn(rows: TrailColumn.today)
                Text("Pinch out for the week")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Days, zoomed out to the week: where the time went, then each day as a short thread with
    /// its journal line.
    struct S1Week: View {
        struct Day: Identifiable {
            var id: String { name }
            let name: String
            let date: String
            let stops: [(from: Double, to: Double)]
            let line: String
            var now: Double?
        }

        static let days: [Day] = [
            Day(
                name: "Wed", date: "18", stops: [(8.2, 9), (9.3, 17.8), (18.2, 19.2)],
                line: "Gym after work. The new deadlift felt fine."),
            Day(
                name: "Thu", date: "19", stops: [(9.3, 17.5), (19, 23.4)],
                line: "Leo cooked, and we stayed up too late planning Lisbon."),
            Day(
                name: "Fri", date: "20", stops: [(19.6, 22.2)],
                line: "Worked from home. Dinner at Orrin's with Omar."),
            Day(
                name: "Sat", date: "21", stops: [(10.5, 13.6), (13.9, 14.6)],
                line: "Up the hill with Mira before the rain."),
            Day(
                name: "Sun", date: "22", stops: [(10, 10.6)],
                line: "A short run, then nothing at all."),
            Day(
                name: "Mon", date: "23", stops: [(9.2, 17.6), (18, 18.9)],
                line: "The office, the gym, an early night."),
            Day(
                name: "Tue", date: "24",
                stops: [(8.2, 9), (9.3, 13.4), (13.8, 15.2), (15.7, 16.5)],
                line: "So far: the café, the office, Northwind.", now: 16.5),
        ]

        var body: some View {
            S1Page(lens: .days) {
                ZoomHeader(title: "Your week", subtitle: "18 – 24 November", zoom: 1)
                VStack(alignment: .leading, spacing: 8) {
                    MapCard(
                        scene: .spots(
                            LifeData.week,
                            labels: [LifeData.office, LifeData.gym, LifeData.leo, LifeData.home],
                            spread: 15),
                        look: .halftone, height: 210)
                    Text("Where the time went, by hours spent, not by pings. Home isn't counted.")
                        .font(.caption)
                        .foregroundStyle(.ariTertiary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.days) { day in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Text(day.name).font(.caption.weight(.semibold))
                                Text(day.date).font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(day.now == nil ? Color.ariTertiary : .ariText)
                            .frame(width: 30)
                            VStack(alignment: .leading, spacing: 6) {
                                DayStrip(stops: day.stops, now: day.now)
                                Text(day.line)
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(day.now == nil ? Color.ariSecondary : .ariText)
                            }
                        }
                    }
                }
                Text("Pinch out for the month, and the year")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Days, zoomed out to the year: the thread folds back and forth a month a row, with chapters
    /// beside it, trips as loops off it and the days you'd want to find as knots.
    struct S1Year: View {
        var body: some View {
            S1Page(lens: .days) {
                ZoomHeader(title: "2026", subtitle: "So far · 4 chapters · 4 trips", zoom: 3)
                YearThread()
                    .frame(height: 560)
                Text("Pinch out again for every year")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    struct YearThread: View {
        static let months = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        /// Chapters: first and last month (0-based), and the name.
        static let chapters: [(Int, Int, String)] = [
            (0, 2, "Winter at the old job"), (3, 5, "Leaving, then Lisbon"),
            (6, 7, "The long summer"), (8, 10, "The Northwind autumn"),
        ]
        /// Trips: month, where in it (0…1), the name.
        static let trips: [(Int, Double, String)] = [
            (2, 0.55, "London · 3 days"), (4, 0.4, "Lisbon · 6 days"),
            (7, 0.5, "Skye · 4 days"), (9, 0.7, "Glasgow · 2 days"),
        ]
        /// Knots worth finding: month, where in it, a few words.
        static let knots: [(Int, Double, String)] = [
            (3, 0.95, "Last day at the old job"), (5, 0.3, "Leo's 30th"),
            (8, 0.45, "First 10k"), (10, 0.77, "Northwind final"),
        ]

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let left: CGFloat = 54
                let right = width - 128
                let rowHeight: CGFloat = 44
                let top: CGFloat = 16
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(in: &context, left: left, right: right, top: top, row: rowHeight)
                    }
                    ForEach(0..<12, id: \.self) { m in
                        Text(Self.months[m])
                            .font(.caption2)
                            .foregroundStyle(m > 10 ? Color.ariTertiary.opacity(0.5) : .ariTertiary)
                            .position(x: 12, y: top + CGFloat(m) * rowHeight)
                    }
                    ForEach(Array(Self.chapters.enumerated()), id: \.offset) { _, chapter in
                        let y0 = top + CGFloat(chapter.0) * rowHeight
                        let y1 = top + CGFloat(chapter.1) * rowHeight
                        HStack(spacing: 8) {
                            Rectangle().fill(Color.ariLine).frame(width: 1, height: y1 - y0 + 14)
                            Text(chapter.2)
                                .font(.system(.footnote, design: .serif).weight(.semibold))
                                .foregroundStyle(.ariSecondary)
                                .frame(width: 92, alignment: .leading)
                        }
                        .position(x: right + 30 + 50, y: (y0 + y1) / 2)
                    }
                    ForEach(Array(Self.trips.enumerated()), id: \.offset) { _, trip in
                        let p = point(
                            trip.0, trip.1, left: left, right: right, top: top, row: rowHeight)
                        Text(trip.2)
                            .font(.caption2)
                            .foregroundStyle(lampColor)
                            .fixedSize()
                            .frame(width: 110, alignment: .leading)
                            .position(x: p.x + 14 + 55, y: p.y + 12)
                    }
                    ForEach(Array(Self.knots.enumerated()), id: \.offset) { _, knot in
                        let p = point(
                            knot.0, knot.1, left: left, right: right, top: top, row: rowHeight)
                        Text(knot.2)
                            .font(.caption2.weight(knot.0 == 10 ? .semibold : .regular))
                            .foregroundStyle(knot.0 == 10 ? Color.ariText : .ariTertiary)
                            .fixedSize()
                            .position(x: min(max(p.x, 60), right - 30), y: p.y - 13)
                    }
                }
            }
        }

        private func point(
            _ month: Int, _ at: Double, left: CGFloat, right: CGFloat, top: CGFloat, row: CGFloat
        ) -> CGPoint {
            let forward = month.isMultiple(of: 2)
            let f = forward ? at : 1 - at
            return CGPoint(x: left + CGFloat(f) * (right - left), y: top + CGFloat(month) * row)
        }

        private func draw(
            in context: inout GraphicsContext, left: CGFloat, right: CGFloat, top: CGFloat,
            row: CGFloat
        ) {
            let nowMonth = 10
            let nowAt = 0.77
            var past = Path()
            var ahead = Path()
            func dots(_ points: [CGPoint], isPast: (Int) -> Bool) {
                for (i, p) in points.enumerated() {
                    if isPast(i) {
                        past.addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                    } else if i % 2 == 0 {
                        ahead.addEllipse(
                            in: CGRect(x: p.x - 0.8, y: p.y - 0.8, width: 1.6, height: 1.6))
                    }
                }
            }
            for m in 0..<12 {
                let y = top + CGFloat(m) * row
                let forward = m.isMultiple(of: 2)
                var points: [CGPoint] = []
                var x = left
                while x <= right {
                    points.append(CGPoint(x: forward ? x : right - (x - left), y: y))
                    x += 4
                }
                let count = points.count
                dots(points) { i in
                    m < nowMonth || (m == nowMonth && Double(i) / Double(count) < nowAt)
                }
                // The turn down to the next month.
                if m < 11 {
                    let cx = forward ? right : left
                    var turn: [CGPoint] = []
                    var a = -CGFloat.pi / 2
                    while a <= CGFloat.pi / 2 {
                        let s = forward ? cos(a) : -cos(a)
                        turn.append(CGPoint(x: cx + s * row / 2, y: y + row / 2 + sin(a) * row / 2))
                        a += 4 / (row / 2)
                    }
                    dots(turn) { _ in m < nowMonth }
                }
            }
            context.fill(past, with: .color(.ariSecondary.opacity(0.7)))
            context.fill(ahead, with: .color(.ariTertiary.opacity(0.5)))
            // Trips: a loop off the thread.
            for trip in Self.trips {
                let p = point(trip.0, trip.1, left: left, right: right, top: top, row: row)
                var loop = Path()
                var a: CGFloat = 0
                while a < 2 * .pi {
                    let q = CGPoint(x: p.x + sin(a) * 9, y: p.y + 10 - cos(a) * 10)
                    loop.addEllipse(in: CGRect(x: q.x - 1.3, y: q.y - 1.3, width: 2.6, height: 2.6))
                    a += 0.42
                }
                context.fill(loop, with: .color(lampColor.opacity(0.85)))
            }
            // Knots.
            for knot in Self.knots {
                let p = point(knot.0, knot.1, left: left, right: right, top: top, row: row)
                var path = Path()
                for dx in stride(from: -6.0, through: 6.0, by: 4.0) {
                    path.addEllipse(
                        in: CGRect(x: p.x + dx - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8))
                }
                context.fill(path, with: .color(knot.0 == nowMonth ? .ariText : .ariSecondary))
            }
            // Now.
            let now = point(nowMonth, nowAt, left: left, right: right, top: top, row: row)
            let ring = CGRect(x: now.x + 10, y: now.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
            context.stroke(
                Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText), lineWidth: 1.3)
            context.fill(Path(ellipseIn: ring.insetBy(dx: 3.8, dy: 3.8)), with: .color(.ariText))
        }
    }

    // MARK: - Going on, as threads beside time

    struct Matter: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let status: String
        let line: String
        /// Days from 1 October.
        let from: Double
        let to: Double?
        let knots: [Double]
        var lit = false
    }

    struct S1GoingOn: View {
        static let matters: [Matter] = [
            Matter(
                symbol: "briefcase.fill", title: "Northwind", status: "Final today",
                line: "Went well, I think. They said they'd write by Friday.", from: 5, to: nil,
                knots: [5, 19, 35, 54], lit: true),
            Matter(
                symbol: "figure.run", title: "Spring 10k", status: "Week 4 of 10",
                line: "Three runs a week. Tonight's is with Leo.", from: 25, to: nil,
                knots: [25, 29, 32, 36, 39, 43, 46, 50, 53, 57, 60, 64, 67, 71, 74]),
            Matter(
                symbol: "gift.fill", title: "Mira's birthday", status: "A week on Friday",
                line: "The ceramics class she mentioned, booked for two.", from: 40, to: 64,
                knots: [40, 51]),
            Matter(
                symbol: "airplane", title: "Lisbon in March", status: "Flights held till Sunday",
                line: "Leo's in. Omar's a maybe.", from: 32, to: nil, knots: [32, 48]),
            Matter(
                symbol: "wrench.adjustable.fill", title: "The boiler",
                status: "Fixed, keeping an eye",
                line: "If it drips again, I'll chase the engineer.", from: 33, to: 50,
                knots: [33, 41, 50]),
        ]

        var body: some View {
            S1Page(lens: .goingOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Going on").font(.ariTitle).foregroundStyle(.ariText)
                    Text("5 threads beside your days · the line is today")
                        .font(.footnote).foregroundStyle(.ariTertiary)
                }
                MonthAxis()
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Self.matters) { matter in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 10) {
                                DotGlyph(symbol: matter.symbol, side: 30)
                                Text(matter.title).font(.ariName).foregroundStyle(.ariText)
                                Spacer()
                                Text(matter.status)
                                    .font(.caption)
                                    .foregroundStyle(matter.lit ? Color.ariText : .ariTertiary)
                            }
                            MatterThread(matter: matter)
                            Text(matter.line)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.ariSecondary)
                        }
                    }
                }
                .overlay { NowLine() }
                Text("Ended this year: 14 threads")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
        }
    }

    /// Oct · Nov · Dec · Jan across the page, as the matters' threads run.
    struct MonthAxis: View {
        var body: some View {
            GeometryReader { geometry in
                ForEach(Array(["Oct", "Nov", "Dec", "Jan"].enumerated()), id: \.offset) { i, m in
                    Text(m)
                        .font(.caption2)
                        .foregroundStyle(.ariTertiary)
                        .position(
                            x: MatterThread.x(Double(i) * 30.5 + 15, geometry.size.width), y: 6)
                }
            }
            .frame(height: 12)
        }
    }

    struct NowLine: View {
        var body: some View {
            GeometryReader { geometry in
                let x = MatterThread.x(54, geometry.size.width)
                Path { path in
                    var y: CGFloat = -26
                    while y < geometry.size.height {
                        path.addEllipse(in: CGRect(x: x - 0.8, y: y, width: 1.6, height: 1.6))
                        y += 5
                    }
                }
                .fill(Color.ariText.opacity(0.35))
            }
            .allowsHitTesting(false)
        }
    }

    struct MatterThread: View {
        let matter: Matter

        static func x(_ day: Double, _ width: CGFloat) -> CGFloat {
            CGFloat(day / 122) * width
        }

        var body: some View {
            Canvas { context, size in
                let y = size.height / 2
                let now = 54.0
                let end = matter.to ?? 122
                var past = Path()
                var ahead = Path()
                var d = matter.from
                while d <= end {
                    let x = Self.x(d, size.width)
                    if d <= now {
                        past.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        d += 4 / Double(size.width) * 122
                    } else {
                        ahead.addEllipse(
                            in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        d += 7 / Double(size.width) * 122
                    }
                }
                context.fill(past, with: .color(.ariSecondary.opacity(0.7)))
                context.fill(ahead, with: .color(.ariTertiary.opacity(0.55)))
                for knot in matter.knots {
                    let x = Self.x(knot, size.width)
                    let r: CGFloat = knot == 54 && matter.lit ? 4 : 2.6
                    let shade: Color =
                        knot > now
                        ? .ariTertiary : (knot == 54 && matter.lit ? .ariText : .ariSecondary)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(shade))
                }
                if matter.to != nil, let last = matter.to, last < now {
                    let x = Self.x(last, size.width)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                        with: .color(.ariTertiary), lineWidth: 1)
                }
            }
            .frame(height: 12)
        }
    }

    // MARK: - Your places

    struct S1Places: View {
        var range = 1
        var look: MapLook = .halftone

        static let rows: [(LifeData.Spot, String)] = [
            (LifeData.Spot(place: LifeData.home, hours: 160, visits: 30), "awake hours only"),
            (LifeData.Spot(place: LifeData.office, hours: 118, visits: 19), "19 days"),
            (LifeData.Spot(place: LifeData.gym, hours: 22, visits: 14), "14 visits, mostly 07:00"),
            (LifeData.Spot(place: LifeData.cafe, hours: 15, visits: 17), "17 mornings"),
            (LifeData.Spot(place: LifeData.leo, hours: 12, visits: 4), "4 evenings"),
            (LifeData.Spot(place: LifeData.meadows, hours: 11, visits: 10), "10 runs"),
            (LifeData.Spot(place: LifeData.mira, hours: 9, visits: 5), "5 visits"),
        ]

        var body: some View {
            S1Page(lens: .places) {
                ZoomHeader(
                    title: "Your places", subtitle: "November · 23 places · 2 new", zoom: range,
                    levels: ["Week", "Month", "Year"])
                MapCard(
                    scene: .spots(
                        LifeData.month,
                        labels: [LifeData.office, LifeData.gym, LifeData.home, LifeData.cafe],
                        spread: 15),
                    look: look, height: 230)
                VStack(spacing: 16) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            DotGlyph(symbol: row.0.place.symbol, side: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.0.place.name).font(.ariName).foregroundStyle(.ariText)
                                Text(row.0.place.what).font(.caption).foregroundStyle(.ariTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("\(Int(row.0.hours)) h")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.ariSecondary)
                                HoursDots(fraction: row.0.hours / 160, count: 10)
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    DotGlyph(symbol: "questionmark", side: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("One I don't know yet").font(.ariName).foregroundStyle(.ariText)
                        Text("Dalry, last Tuesday evening, 2 hours").font(.caption).foregroundStyle(
                            .ariTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.ariTertiary)
                }
                .padding(12)
                .background(
                    Color.ariSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
#endif
