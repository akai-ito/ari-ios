#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Days, zoomed in on today: 1a's look

    struct R2Day: View {
        var body: some View {
            LifeScroll(section: .days) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center) {
                        Text("Tuesday").font(.ariTitle).foregroundStyle(.ariText)
                        Spacer()
                        ZoomScale(current: 0)
                    }
                    Text("24 November · 4 places · 6.2 km")
                        .font(.footnote).foregroundStyle(.ariTertiary)
                }
                MapCard(scene: .today(), look: .muted, height: 200, zoom: 14)
                KumoSays(
                    mood: .proud,
                    text:
                        "The final's behind you. I kept the day as you went; I'll write it up tonight.",
                    size: 34)
                TrailColumn(rows: TrailColumn.today)
            }
        }
    }

    // MARK: - Week and month: the full-screen lit map with a sheet of days

    extension MapScene {
        /// The city, filling the screen, lit by where the time went (home included).
        static func lit(_ spots: [LifeData.Spot], full: Double, labels: [MapLabel], kumo: Bool)
            -> MapScene
        {
            MapScene(
                region: LifeData.wide(lat: 55.9373, lon: -3.1915, span: 0.12),
                heat: LifeData.glow(spots, full: full), spread: 21, labels: labels,
                kumo: kumo ? LifeData.office.coordinate : nil, kumoSize: 34, kumoMood: .calm)
        }
    }

    struct SheetTitle: View {
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ariHeading).foregroundStyle(.ariText)
                Spacer()
                Text(detail).font(.footnote).foregroundStyle(.ariTertiary)
            }
        }
    }

    struct R2Week: View {
        var body: some View {
            LifeOverMap(section: .days, zoom: 1, sheetHeight: 372) {
                LifeMap(
                    scene: .lit(
                        LifeData.week, full: 10,
                        labels: [
                            MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                            MapLabel(text: "The office", coordinate: LifeData.office.coordinate),
                            MapLabel(text: "The gym", coordinate: LifeData.gym.coordinate),
                            MapLabel(text: "Leo's", coordinate: LifeData.leo.coordinate),
                            MapLabel(
                                text: "Orrin's · 2 h", coordinate: LifeData.orrins.coordinate,
                                below: false),
                            MapLabel(
                                text: "The hill", coordinate: LifeData.hill.coordinate,
                                below: false),
                        ], kumo: true),
                    zoom: 14, credit: false)
            } sheet: {
                VStack(alignment: .leading, spacing: 16) {
                    SheetTitle(title: "Your week", detail: "18 – 24 November")
                    KumoSays(
                        mood: .calm,
                        text: "Home and the office, mostly. The gym four times, Leo's on Thursday.",
                        size: 30)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(S1Week.days.reversed().prefix(4)) { day in
                            WeekDayRow(day: day)
                        }
                    }
                }
            }
        }
    }

    struct WeekDayRow: View {
        let day: S1Week.Day

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(day.name).font(.caption.weight(.semibold))
                    Text(day.date).font(.caption2.monospacedDigit())
                }
                .foregroundStyle(day.now == nil ? Color.ariTertiary : .ariText)
                .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    DayStrip(stops: day.stops, now: day.now)
                    Text(day.line)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(day.now == nil ? Color.ariSecondary : .ariText)
                        .lineLimit(1)
                }
            }
        }
    }

    struct R2Month: View {
        static let weeks: [(String, String)] = [
            ("23 – 29", "The final, and a lot of the office."),
            ("16 – 22", "Up the hill with Mira. Orrin's with Omar."),
            ("9 – 15", "The boiler again. Lisbon talk at Leo's."),
        ]

        var body: some View {
            LifeOverMap(section: .days, zoom: 2, sheetHeight: 396) {
                LifeMap(
                    scene: .lit(
                        LifeData.month, full: 40,
                        labels: [
                            MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                            MapLabel(text: "The office", coordinate: LifeData.office.coordinate),
                            MapLabel(text: "The gym", coordinate: LifeData.gym.coordinate),
                            MapLabel(text: "Leo's", coordinate: LifeData.leo.coordinate),
                            MapLabel(
                                text: "Orrin's", coordinate: LifeData.orrins.coordinate,
                                below: false),
                            MapLabel(
                                text: "Dalry · ?", coordinate: LifeData.unknown.coordinate,
                                below: false),
                        ], kumo: false),
                    zoom: 14, credit: false)
            } sheet: {
                VStack(alignment: .leading, spacing: 16) {
                    SheetTitle(title: "November", detail: "23 places · 2 new")
                    ChapterRow(
                        name: "The Northwind autumn", detail: "Since October · you're in it",
                        from: 9, to: LifeData.nowMonth, current: true, letters: true)
                    KumoSays(
                        mood: .calm,
                        text:
                            "Home, the office, the gym most mornings. One new place I can't name.",
                        size: 30)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.weeks, id: \.0) { week in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(week.0)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.ariTertiary)
                                    .frame(width: 52, alignment: .leading)
                                Text(week.1)
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(
                                        week.0 == "23 – 29" ? Color.ariText : .ariSecondary
                                    )
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chapters as spans on the year

    /// A chapter: its name, and its months lit on the year's thread, with trips as amber knots.
    struct ChapterRow: View {
        let name: String
        var detail: String?
        let from: Double
        let to: Double
        var current = false
        var letters = false

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(.footnote, design: .serif).weight(.semibold))
                        .foregroundStyle(current ? Color.ariText : .ariSecondary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(.ariTertiary).lineLimit(1)
                    }
                }
                .frame(width: 160, alignment: .leading)
                VStack(spacing: 3) {
                    YearSpan(from: from, to: to, current: current).frame(height: 12)
                    if letters { MonthLetters() }
                }
            }
        }
    }

    struct MonthLetters: View {
        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array("JFMAMJJASOND".enumerated()), id: \.offset) { i, letter in
                    Text(String(letter))
                        .font(.system(size: 9))
                        .foregroundStyle(
                            Double(i) > LifeData.nowMonth
                                ? Color.ariTertiary.opacity(0.5) : .ariTertiary
                        )
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    struct YearSpan: View {
        let from: Double
        let to: Double
        var current = false

        var body: some View {
            Canvas { context, size in
                func x(_ month: Double) -> CGFloat { CGFloat(month / 12) * size.width }
                let y = size.height / 2
                var faint = Path()
                var at: CGFloat = 1
                while at <= size.width {
                    let r: CGFloat = at <= x(LifeData.nowMonth) ? 0.8 : 0.6
                    faint.addEllipse(in: CGRect(x: at - r, y: y - r, width: r * 2, height: r * 2))
                    at += 5
                }
                context.fill(faint, with: .color(.ariTertiary.opacity(0.5)))
                var span = Path()
                at = x(from) + 2
                while at <= x(to) - 1 {
                    span.addEllipse(in: CGRect(x: at - 2, y: y - 2, width: 4, height: 4))
                    at += 4.2
                }
                context.fill(span, with: .color(current ? .ariText : .ariSecondary))
                for trip in LifeData.trips where trip.month >= from && trip.month < to {
                    let p = x(trip.month)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p - 4.2, y: y - 4.2, width: 8.4, height: 8.4)),
                        with: .color(lampColor))
                }
                if current {
                    let p = x(LifeData.nowMonth)
                    let ring = CGRect(x: p - 5.5, y: y - 5.5, width: 11, height: 11)
                    context.fill(Path(ellipseIn: ring), with: .color(.ariSurface))
                    context.stroke(
                        Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText),
                        lineWidth: 1.2)
                    context.fill(
                        Path(ellipseIn: ring.insetBy(dx: 3.6, dy: 3.6)), with: .color(.ariText))
                }
            }
        }
    }

    // MARK: - The year: a globe with the trips lit

    struct R2Year: View {
        var body: some View {
            LifeOverMap(section: .days, zoom: 3, sheetHeight: 400) {
                GlobeGround()
            } sheet: {
                VStack(alignment: .leading, spacing: 15) {
                    SheetTitle(title: "2026", detail: "4 chapters · 4 trips")
                    KumoSays(
                        mood: .bright,
                        text:
                            "Three continents. India was the longest: two weeks, for Anya's wedding.",
                        size: 30)
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 12) {
                            Color.clear.frame(width: 160, height: 1)
                            MonthLetters()
                        }
                        ForEach(Array(LifeData.chapters.enumerated()), id: \.offset) { _, c in
                            ChapterRow(
                                name: c.name, detail: tripsIn(c.from, c.to), from: c.from,
                                to: c.to, current: c.to == LifeData.nowMonth)
                        }
                    }
                }
            }
        }

        private func tripsIn(_ from: Double, _ to: Double) -> String {
            let names = LifeData.trips.filter { $0.month >= from && $0.month < to }.map(\.country)
            return names.isEmpty ? "At home" : names.joined(separator: " · ")
        }
    }

    struct GlobeGround: View {
        var lat0 = 31.0
        var lon0 = 60.0
        var radius: CGFloat = 200
        var centerY: CGFloat = 352

        static let home = CLLocationCoordinate2D(latitude: 55.95, longitude: -3.19)

        var body: some View {
            GeometryReader { geometry in
                let c = CGPoint(x: geometry.size.width / 2, y: centerY)
                ZStack(alignment: .topLeading) {
                    Color.ariBackground
                    Canvas { context, size in
                        drawSky(in: &context, size: size, c: c)
                    }
                    if let image = Globe.image(
                        lat0: lat0, lon0: lon0, side: Int(radius * 2 * 3))
                    {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: radius * 2, height: radius * 2)
                            .colorMultiply(Color(red: 0.86, green: 0.91, blue: 1.0))
                            .saturation(0.6)
                            .position(c)
                    }
                    Canvas { context, _ in
                        drawTrips(in: &context, c: c)
                    }
                    ForEach(labels(c: c), id: \.0) { label in
                        Text(label.0)
                            .font(label.2 ? .caption.weight(.semibold) : .caption2)
                            .foregroundStyle(label.2 ? Color.ariText : .ariSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.ariBackground.opacity(0.72), in: Capsule())
                            .fixedSize()
                            .position(label.1)
                    }
                }
            }
        }

        private func project(_ lat: Double, _ lon: Double) -> (x: Double, y: Double, z: Double) {
            Globe.rotate(lat: lat, lon: lon, lat0: lat0, lon0: lon0)
        }

        private func screen(_ p: (x: Double, y: Double, z: Double), _ c: CGPoint) -> CGPoint {
            CGPoint(x: c.x + CGFloat(p.x) * radius, y: c.y - CGFloat(p.y) * radius)
        }

        private func drawSky(in context: inout GraphicsContext, size: CGSize, c: CGPoint) {
            var stars = Path()
            var seed: UInt64 = 7
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(UInt32.max >> 1)
            }
            for _ in 0..<90 {
                let p = CGPoint(x: next() * size.width, y: next() * size.height)
                guard hypot(p.x - c.x, p.y - c.y) > radius + 18 else {
                    _ = next()
                    continue
                }
                let r = 0.5 + next() * 0.7
                stars.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            context.fill(stars, with: .color(.ariSecondary.opacity(0.35)))
            let halo = radius + 26
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: radius / halo - 0.02),
                        .init(color: Color.ariBone.opacity(0.1), location: radius / halo),
                        .init(color: .clear, location: 1),
                    ]), center: c, startRadius: 0, endRadius: halo))
        }

        private func drawTrips(in context: inout GraphicsContext, c: CGPoint) {
            let home = project(Self.home.latitude, Self.home.longitude)
            var arcs = Path()
            for trip in LifeData.trips {
                let to = project(trip.lat, trip.lon)
                let points = Globe.arc(from: home, to: to, lift: 0.16)
                var carry = 0.0
                for (a, b) in zip(points, points.dropFirst()) {
                    guard a.z > -0.05 || a.x * a.x + a.y * a.y > 1 else { continue }
                    let pa = screen(a, c)
                    let pb = screen(b, c)
                    let length = Double(hypot(pb.x - pa.x, pb.y - pa.y))
                    var at = carry
                    while at <= length {
                        let t = CGFloat(at / max(length, 0.001))
                        let q = CGPoint(x: pa.x + (pb.x - pa.x) * t, y: pa.y + (pb.y - pa.y) * t)
                        arcs.addEllipse(in: CGRect(x: q.x - 1, y: q.y - 1, width: 2, height: 2))
                        at += 4.5
                    }
                    carry = at - length
                }
            }
            context.fill(arcs, with: .color(.ariBone.opacity(0.7)))
            var glows: [(CGPoint, Double)] = [(screen(home, c), 1)]
            glows.append(
                (screen(project(51.51, -0.13), c), LifeData.glow(9 * 14, full: 500)))
            for trip in LifeData.trips {
                glows.append(
                    (
                        screen(project(trip.lat, trip.lon), c),
                        LifeData.glow(Double(trip.days) * 14, full: 500)
                    ))
            }
            for (p, w) in glows {
                let r = 16 * (0.8 + 1.1 * w)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            lampColor.opacity(0.35 + 0.6 * w), lampColor.opacity(0.1 + 0.2 * w),
                            lampColor.opacity(0),
                        ]), center: p, startRadius: 0, endRadius: r))
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                    with: .color(lampColor))
            }
        }

        private func labels(c: CGPoint) -> [(String, CGPoint, Bool)] {
            func at(_ lat: Double, _ lon: Double, dx: CGFloat = 0, dy: CGFloat) -> CGPoint {
                let p = screen(project(lat, lon), c)
                return CGPoint(x: p.x + dx, y: p.y + dy)
            }
            return [
                ("Home", at(55.95, -3.19, dy: -17), true),
                ("Portugal · 8 days", at(38.72, -9.14, dx: 58, dy: 1), false),
                ("Morocco · 6 days", at(31.63, -7.99, dx: 44, dy: 19), false),
                ("India · 14 days", at(9.93, 76.27, dy: 18), false),
                ("Japan · 12 days", at(35.01, 135.77, dx: -10, dy: -18), false),
            ]
        }
    }

    /// The world drawn on a sphere from flat map tiles (an orthographic view), for the year.
    enum Globe {
        private static var cache: [String: UIImage] = [:]

        /// A place on the sphere, turned so that (lat0, lon0) faces you: x right, y up, z out.
        static func rotate(lat: Double, lon: Double, lat0: Double, lon0: Double) -> (
            x: Double, y: Double, z: Double
        ) {
            let p = lat * .pi / 180
            let l = (lon - lon0) * .pi / 180
            let p0 = lat0 * .pi / 180
            return (
                cos(p) * sin(l),
                cos(p0) * sin(p) - sin(p0) * cos(p) * cos(l),
                sin(p0) * sin(p) + cos(p0) * cos(p) * cos(l)
            )
        }

        /// The way between two places as a flight: along the sphere, lifted in the middle.
        static func arc(
            from a: (x: Double, y: Double, z: Double), to b: (x: Double, y: Double, z: Double),
            lift: Double
        ) -> [(x: Double, y: Double, z: Double)] {
            (0...60).map { i in
                let t = Double(i) / 60
                var x = a.x + (b.x - a.x) * t
                var y = a.y + (b.y - a.y) * t
                var z = a.z + (b.z - a.z) * t
                let n = (x * x + y * y + z * z).squareRoot()
                let h = (1 + lift * sin(.pi * t)) / max(n, 0.0001)
                x *= h
                y *= h
                z *= h
                return (x, y, z)
            }
        }

        static func image(lat0: Double, lon0: Double, side: Int) -> UIImage? {
            let key = "\(lat0),\(lon0),\(side)"
            if let kept = cache[key] { return kept }
            let zoom = 3
            let count = 8
            let world = 256 * count
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let flat = UIGraphicsImageRenderer(
                size: CGSize(width: world, height: world), format: format
            ).image { _ in
                for x in 0..<count {
                    for y in 0..<count {
                        Tiles.image(style: "esri", zoom: zoom, x: x, y: y)?.draw(
                            in: CGRect(x: x * 256, y: y * 256, width: 256, height: 256))
                    }
                }
            }
            guard let cg = flat.cgImage else { return nil }
            var source = [UInt8](repeating: 0, count: world * world * 4)
            source.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: world, height: world, bitsPerComponent: 8,
                        bytesPerRow: world * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: world, height: world))
            }
            var out = [UInt8](repeating: 0, count: side * side * 4)
            let p0 = lat0 * .pi / 180
            let l0 = lon0 * .pi / 180
            let sp0 = sin(p0)
            let cp0 = cos(p0)
            let w = Double(world)
            let limit = 85.05 * .pi / 180
            source.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for py in 0..<side {
                        let y = 1 - (Double(py) + 0.5) / Double(side) * 2
                        for px in 0..<side {
                            let x = (Double(px) + 0.5) / Double(side) * 2 - 1
                            let r2 = x * x + y * y
                            if r2 > 1 { continue }
                            let rho = r2.squareRoot()
                            let c = asin(min(1, rho))
                            let sc = sin(c)
                            let cc = cos(c)
                            let lat = rho < 1e-9 ? p0 : asin(cc * sp0 + y * sc * cp0 / rho)
                            let lon = l0 + atan2(x * sc, rho * cc * cp0 - y * sc * sp0)
                            let la = max(-limit, min(limit, lat))
                            var u = (lon + .pi) / (2 * .pi)
                            u -= floor(u)
                            let v = (1 - log(tan(la) + 1 / cos(la)) / .pi) / 2
                            let sx = min(world - 1, max(0, Int(u * w)))
                            let sy = min(world - 1, max(0, Int(v * w)))
                            let si = (sy * world + sx) * 4
                            let edge = min(1, (1 - rho) * Double(side) / 2)
                            let shade = (0.5 + 0.6 * cc) * 1.2 * edge
                            let o = (py * side + px) * 4
                            dst[o] = UInt8(min(255, Double(src[si]) * shade))
                            dst[o + 1] = UInt8(min(255, Double(src[si + 1]) * shade))
                            dst[o + 2] = UInt8(min(255, Double(src[si + 2]) * shade))
                            dst[o + 3] = UInt8(255 * edge)
                        }
                    }
                }
            }
            let data = Data(out) as CFData
            guard let provider = CGDataProvider(data: data),
                let image = CGImage(
                    width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true,
                    intent: .defaultIntent)
            else { return nil }
            let result = UIImage(cgImage: image)
            cache[key] = result
            return result
        }
    }
#endif
