#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Headers

    /// The lenses across the top of Life: words, the one you're on lit with a dotted underline.
    struct LensRow: View {
        let lenses: [String]
        let current: Int

        var body: some View {
            HStack(spacing: 18) {
                ForEach(Array(lenses.enumerated()), id: \.offset) { index, lens in
                    VStack(spacing: 5) {
                        Text(lens)
                            .font(.subheadline.weight(index == current ? .semibold : .regular))
                            .foregroundStyle(index == current ? Color.ariText : Color.ariTertiary)
                            .fixedSize()
                        DotRule(count: index == current ? 5 : 0)
                    }
                }
            }
        }
    }

    struct DotRule: View {
        let count: Int
        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<max(count, 1), id: \.self) { _ in
                    Circle().fill(Color.ariBone).frame(width: 3, height: 3)
                }
            }
            .opacity(count == 0 ? 0 : 1)
        }
    }

    /// How far out you've zoomed: Day · Week · Month · Year, the current one lit.
    struct ZoomScale: View {
        var levels = ["Day", "Week", "Month", "Year"]
        let current: Int

        var body: some View {
            HStack(spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Text(level)
                        .fixedSize()
                        .font(.caption.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index == current ? Color.ariBackground : Color.ariTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(index == current ? Color.ariBone : .clear, in: Capsule())
                }
            }
            .padding(3)
            .background(Color.ariField.opacity(0.8), in: Capsule())
            .fixedSize()
        }
    }

    /// Kumo, small, with its line beside it.
    struct KumoSays: View {
        var mood: FaceMood = .calm
        let text: String
        var size: CGFloat = 38

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                KumoFace(mood: mood, size: size, still: true)
                Text(text)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    struct SectionHead: View {
        let text: String
        var body: some View {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.ariTertiary)
        }
    }

    /// A map in a rounded card.
    struct MapCard: View {
        let scene: MapScene
        var look: MapLook = .muted
        var height: CGFloat = 190
        var zoom = 15
        var step: CGFloat = 5

        var body: some View {
            LifeMap(scene: scene, look: look, step: step, zoom: zoom)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.ariLine.opacity(0.6), lineWidth: 0.5)
                }
        }
    }

    /// A row of dots, `fraction` of them lit: time spent, without a chart.
    struct HoursDots: View {
        let fraction: Double
        var count = 12

        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(
                            Double(i) < fraction * Double(count)
                                ? Color.ariBone : Color.ariLine
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    /// A word to tap, quiet: a capsule outline.
    struct Chip: View {
        let text: String
        var lit = false
        var body: some View {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(lit ? Color.ariBackground : Color.ariText)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(lit ? Color.ariBone : Color.clear, in: Capsule())
                .overlay { Capsule().stroke(Color.ariLine, lineWidth: lit ? 0 : 1) }
                .fixedSize()
        }
    }

    // MARK: - Today's trail, as quiet blocks on a thread

    enum TrailRow: Identifiable {
        case stop(
            time: String, name: String, detail: String, minutes: Int, now: Bool, note: String?)
        case move(String)
        case ahead(time: String, title: String, place: String)
        case start(time: String, text: String)

        var id: String {
            switch self {
            case .stop(let time, let name, _, _, _, _): "s\(time)\(name)"
            case .move(let text): "m\(text)"
            case .ahead(let time, let title, _): "a\(time)\(title)"
            case .start(let time, _): "b\(time)"
            }
        }
    }

    struct TrailColumn: View {
        let rows: [TrailRow]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    TrailRowView(row: row)
                }
            }
        }

        static let today: [TrailRow] = [
            .start(time: "07:55", text: "Left home"),
            .move("15 min walk, across the Meadows"),
            .stop(
                time: "08:10", name: "The morning café", detail: "Copperleaf · 50 min",
                minutes: 50, now: false, note: nil),
            .move("20 min walk, up the Mound"),
            .stop(
                time: "09:20", name: "The office", detail: "Hearthside · 4 h 05", minutes: 245,
                now: false, note: nil),
            .move("25 min, the bus down Leith Walk"),
            .stop(
                time: "13:50", name: "Northwind", detail: "Their office · 1 h 20", minutes: 80,
                now: false, note: "Northwind final · 14:00"),
            .move("30 min, back up the Walk"),
            .stop(
                time: "15:40", name: "The office", detail: "Since 15:40", minutes: 50, now: true,
                note: nil),
            .ahead(time: "17:30", title: "Run with Leo", place: "The Meadows loop"),
            .ahead(time: "19:30", title: "Dinner with Mira", place: "Orrin's, Stockbridge"),
        ]
    }

    struct TrailRowView: View {
        let row: TrailRow

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                Text(time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isAhead ? Color.ariTertiary.opacity(0.7) : .ariTertiary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.top, timeTop)
                ThreadSegment(kind: segment, height: height)
                    .frame(width: 26)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height, alignment: .top)
        }

        private var isAhead: Bool { if case .ahead = row { true } else { false } }

        private var time: String {
            switch row {
            case .stop(let time, _, _, _, _, _), .ahead(let time, _, _), .start(let time, _): time
            case .move: ""
            }
        }

        private var timeTop: CGFloat {
            switch row {
            case .stop: 12
            default: 2
            }
        }

        private var segment: ThreadSegment.Kind {
            switch row {
            case .stop(_, _, _, _, let now, _): now ? .now : .knot
            case .move: .travelled
            case .ahead: .ahead
            case .start: .start
            }
        }

        private var height: CGFloat {
            switch row {
            case .stop(_, _, _, let minutes, _, let note):
                max(58, min(118, 40 + CGFloat(minutes) * 0.28)) + (note == nil ? 0 : 26)
            case .move: 34
            case .ahead: 50
            case .start: 26
            }
        }

        @ViewBuilder
        private var content: some View {
            switch row {
            case .stop(_, let name, let detail, _, let now, let note):
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name).font(.ariName).foregroundStyle(.ariText)
                        if now {
                            Text("now")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.ariBackground)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.ariBone, in: Capsule())
                        }
                    }
                    Text(detail).font(.footnote).foregroundStyle(.ariTertiary)
                    if let note {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").font(.caption2)
                            Text(note).font(.caption)
                        }
                        .foregroundStyle(.ariSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.ariField, in: Capsule())
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    Color.ariSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.vertical, 3)
            case .move(let text):
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                    .padding(.leading, 4)
                    .frame(maxHeight: .infinity)
            case .ahead(_, let title, let place):
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline).foregroundStyle(.ariSecondary)
                    Text(place).font(.caption).foregroundStyle(.ariTertiary)
                }
                .padding(.leading, 4)
            case .start(_, let text):
                Text(text).font(.caption).foregroundStyle(.ariTertiary).padding(.leading, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// One stretch of the day's thread, drawn down the page.
    struct ThreadSegment: View {
        enum Kind { case knot, now, travelled, ahead, start }
        let kind: Kind
        let height: CGFloat

        var body: some View {
            Canvas { context, size in
                let x = size.width / 2
                switch kind {
                case .travelled, .start:
                    var path = Path()
                    var y: CGFloat = kind == .start ? 9 : 1
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        y += 4
                    }
                    context.fill(path, with: .color(.ariSecondary.opacity(0.7)))
                    if kind == .start {
                        let ring = CGRect(x: x - 4, y: 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: ring), with: .color(.ariSecondary))
                    }
                case .knot, .now:
                    var path = Path()
                    var y: CGFloat = 8
                    while y < size.height - 6 {
                        path.addEllipse(in: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
                        y += 4.6
                    }
                    context.fill(path, with: .color(kind == .now ? .ariText : .ariSecondary))
                    if kind == .now {
                        let ring = CGRect(x: x - 6, y: 14, width: 12, height: 12)
                        context.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
                        context.stroke(
                            Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText),
                            lineWidth: 1.3)
                        context.fill(
                            Path(ellipseIn: ring.insetBy(dx: 3.8, dy: 3.8)), with: .color(.ariText))
                    }
                case .ahead:
                    var path = Path()
                    var y: CGFloat = 0
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        y += 7
                    }
                    context.fill(path, with: .color(.ariTertiary.opacity(0.55)))
                    let knot = CGRect(x: x - 3.5, y: 4, width: 7, height: 7)
                    context.stroke(
                        Path(ellipseIn: knot), with: .color(.ariTertiary), lineWidth: 1.2)
                }
            }
            .frame(height: height)
        }
    }

    // MARK: - A day as a short horizontal thread (for the week)

    struct DayStrip: View {
        /// Stops in hours since midnight, with how bright each knot is.
        let stops: [(from: Double, to: Double)]
        var now: Double?
        var ahead = false

        var body: some View {
            Canvas { context, size in
                let first = 7.0
                let last = 24.0
                func x(_ h: Double) -> CGFloat {
                    CGFloat((min(max(h, first), last) - first) / (last - first)) * (size.width - 8)
                        + 4
                }
                let y = size.height / 2
                let nowX = now.map(x) ?? (ahead ? 0 : size.width)
                var travelled = Path()
                var later = Path()
                var at: CGFloat = 0
                while at <= size.width {
                    if at <= nowX {
                        travelled.addEllipse(
                            in: CGRect(x: at - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                        at += 4
                    } else {
                        later.addEllipse(
                            in: CGRect(x: at - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                        at += 7
                    }
                }
                context.fill(travelled, with: .color(.ariSecondary.opacity(0.6)))
                context.fill(later, with: .color(.ariTertiary.opacity(0.5)))
                for stop in stops {
                    var knot = Path()
                    var dot = x(stop.from)
                    while dot <= max(x(stop.from) + 1, x(stop.to)) {
                        knot.addEllipse(
                            in: CGRect(x: dot - 2.2, y: y - 2.2, width: 4.4, height: 4.4))
                        dot += 4.4
                    }
                    let past = !ahead && (now.map { stop.to < $0 } ?? true)
                    context.fill(
                        knot, with: .color(past ? .ariSecondary : .ariTertiary.opacity(0.7)))
                }
                if let now {
                    let p = x(now)
                    let ring = CGRect(x: p - 5, y: y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
                    context.stroke(
                        Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText),
                        lineWidth: 1.2)
                    context.fill(
                        Path(ellipseIn: ring.insetBy(dx: 3.4, dy: 3.4)), with: .color(.ariText))
                }
            }
            .frame(height: 14)
        }
    }

    // MARK: - A sheet over a map

    /// A sheet resting over the map at a height, Maps-like but in Ito's surface.
    struct RestingSheet<Content: View>: View {
        let height: CGFloat
        @ViewBuilder var content: Content

        var body: some View {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(Color.ariLine)
                        .frame(width: 38, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    content
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: height, alignment: .top)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous
                    )
                    .fill(Color.ariSurface)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Common scenes

    extension MapScene {
        static func today(kumo: Bool = true, labelled: Bool = true) -> MapScene {
            MapScene(
                region: LifeData.todayRegion,
                trails: [
                    LifeData.homeToCafe, LifeData.cafeToOffice, LifeData.officeToNorthwind,
                ],
                faintTrails: [],
                heat: [],
                stops: [
                    LifeData.cafe.coordinate, LifeData.northwind.coordinate,
                    LifeData.home.coordinate,
                ],
                labels: labelled
                    ? [
                        MapLabel(text: "The café · 08:10", coordinate: LifeData.cafe.coordinate),
                        MapLabel(
                            text: "Northwind · 13:50", coordinate: LifeData.northwind.coordinate),
                        MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                    ] : [],
                kumo: kumo ? LifeData.office.coordinate : nil,
                kumoSize: 40, kumoMood: .proud)
        }

        static func spots(
            _ spots: [LifeData.Spot], region: MKCoordinateRegion = LifeData.city,
            labels: [LifePlace] = [], spread: CGFloat = 30
        ) -> MapScene {
            MapScene(
                region: region, heat: LifeData.heat(spots, includingHome: false), spread: spread,
                labels: labels.map { MapLabel(text: $0.name, coordinate: $0.coordinate) })
        }
    }
#endif
