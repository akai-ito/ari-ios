#if DEBUG
    import AriKit
    import CoreText
    import SwiftUI
    import UIKit

    // MARK: - Sleeping Kumo

    /// Kumo asleep on its cushion: dusky, sparse dots, eyes shut in two soft arcs, and z's while
    /// it isn't dreaming. `settling` lifts the top of the pebble a touch, as if thoughts rise off it.
    struct SleepingKumo: View {
        var size: CGFloat = 150
        /// 0 when the dream's done and everything has settled; 1 while dots rise off it.
        var settling: Double = 0
        var zs = false

        var body: some View {
            Color.clear
                .frame(width: size, height: size * 0.92)
                .overlay {
                    Canvas { canvas, area in draw(in: &canvas, area: area) }
                        .frame(width: size * 1.9, height: size * 1.7)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Kumo, asleep")
        }

        private func draw(in canvas: inout GraphicsContext, area: CGSize) {
            let scale = size / 40
            canvas.translateBy(x: area.width / 2, y: area.height / 2)
            canvas.scaleBy(x: scale, y: scale)

            var cushion = Path()
            for x in stride(from: -16.0, through: 16.0, by: 2.2) {
                for y in [18.2, 20.2] {
                    let u = x / 16
                    guard u * u + pow((y - 19.2) / 2.2, 2) <= 1.05 else { continue }
                    let r = 0.55 * (1 - 0.5 * u * u)
                    cushion.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
            canvas.fill(cushion, with: .color(.ariDusk.opacity(0.35)))

            if zs {
                for (i, phase) in [0.25, 0.75].enumerated() {
                    let s = 0.7 + 0.5 * phase
                    let o = CGPoint(x: 19 + 7 * phase, y: -12 - 12 * phase)
                    let z: [(Double, Double)] = [
                        (-2, -2), (0, -2), (2, -2), (0.7, -0.7), (-0.7, 0.7), (-2, 2), (0, 2),
                        (2, 2),
                    ]
                    var dots = Path()
                    for (dx, dy) in z {
                        let r = (1.1 * s + 0.2) / 2
                        dots.addEllipse(
                            in: CGRect(
                                x: o.x + dx * s - r, y: o.y + dy * s - r, width: 2 * r,
                                height: 2 * r))
                    }
                    canvas.fill(dots, with: .color(.ariBone.opacity(i == 0 ? 0.7 : 0.4)))
                }
            }

            canvas.translateBy(x: 0, y: 1.2)
            canvas.rotate(by: .degrees(5))
            var dots = Path()
            let step = 2.9
            var row = 0
            for y in stride(from: -16.0, through: 16.0, by: step * 0.87) {
                let shift = row.isMultiple(of: 2) ? 0 : step / 2
                row += 1
                let b = 15.5
                for x in stride(from: -18.0 + shift, through: 18.0, by: step) {
                    let a = 17.5 * (1 + 0.04 * y / b)
                    guard pow(abs(x / a), 2.3) + pow(abs(y / b), 2.3) <= 1 else { continue }
                    let distance = min(1, hypot(x / 17.5, y / 15.5))
                    var r = step * 0.37 * (1 - 0.38 * distance * distance)
                    // While dreaming, the top rows thin, as if lifting off.
                    if settling > 0, y < -10 {
                        r *= 1 - 0.35 * settling * Seeded.unit(Int(x * 10 + y * 100), 3)
                    }
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
            }
            let fill = Color.ariDusk.mix(with: .ariBone, by: 0.42).mix(
                with: SkyGlyph.lamp, by: 0.05)
            canvas.fill(dots, with: .color(fill))

            // Eyes shut: a gentle downward arc each.
            for side in [-1.0, 1.0] {
                let cx = side * 6.4
                let cy = 0.8
                var arc = Path()
                arc.move(to: CGPoint(x: cx - 2.4, y: cy - 0.6))
                arc.addQuadCurve(
                    to: CGPoint(x: cx + 2.4, y: cy - 0.6), control: CGPoint(x: cx, y: cy + 2.0))
                canvas.stroke(
                    arc, with: .color(.ariBackground),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            }
        }
    }

    // MARK: - Words in dots

    /// A word as points on a halftone grid, filled where the serif letters are.
    enum DotWord {
        static func points(_ word: String, size: CGFloat, step: CGFloat) -> [CGPoint] {
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            let font =
                base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) }
                ?? base
            let ctFont = font as CTFont
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: word, attributes: [.font: font]))
            let path = CGMutablePath()
            for case let run as CTRun in CTLineGetGlyphRuns(line) as NSArray {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for i in 0..<count {
                    if let glyph = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
                        path.addPath(
                            glyph,
                            transform: CGAffineTransform(
                                translationX: positions[i].x, y: positions[i].y))
                    }
                }
            }
            let box = path.boundingBox
            var points: [CGPoint] = []
            var row = 0
            var y = box.minY
            while y <= box.maxY {
                var x = box.minX + (row.isMultiple(of: 2) ? 0 : step / 2)
                while x <= box.maxX {
                    if path.contains(CGPoint(x: x, y: y)) {
                        points.append(CGPoint(x: x - box.midX, y: -(y - box.midY)))
                    }
                    x += step
                }
                y += step * 0.87
                row += 1
            }
            return points
        }
    }

    /// A word on its way: how far it has formed (0 to 1), and how far it has blown away.
    struct WordState {
        let word: String
        var formed: Double = 1
        var gone: Double = 0
    }

    /// Thoughts drifting up off sleeping Kumo, gathering for a moment into a word above it, then
    /// blowing away. Kumo's centre and size, and where the words form, are in the canvas's points.
    struct DriftField: View {
        let words: [WordState]
        let kumoCenter: (CGSize) -> CGPoint
        let kumoSize: CGFloat
        let wordCenter: (CGSize) -> CGPoint
        var fontSize: CGFloat = 40
        var loose = 34
        var time: Double = 0.3

        var body: some View {
            Canvas { canvas, size in
                let kumo = kumoCenter(size)
                let top = CGPoint(x: kumo.x, y: kumo.y - kumoSize * 0.36)
                let spread = kumoSize * 0.6
                let unit = kumoSize / 150
                // Loose thoughts rising.
                for j in 0..<loose {
                    let phase = (Seeded.unit(j, 1) + time * (0.6 + 0.6 * Seeded.unit(j, 2)))
                        .truncatingRemainder(dividingBy: 1)
                    let x =
                        top.x + (Seeded.unit(j, 4) - 0.5) * spread
                        + sin(phase * 6 + Seeded.unit(j, 5) * 10) * 8 * unit
                    let y = top.y - phase * (top.y - wordCenter(size).y + 40 * unit)
                    let r = (0.7 + 0.9 * Seeded.unit(j, 6)) * unit
                    let o = sin(phase * .pi) * 0.55
                    canvas.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                        with: .color(.ariBone.opacity(o)))
                }
                // The words.
                let centre = wordCenter(size)
                for (w, state) in words.enumerated() {
                    let points = DotWord.points(state.word, size: fontSize, step: fontSize * 0.085)
                    for (i, target) in points.enumerated() {
                        let u1 = Seeded.unit(i, 10 + w)
                        let u2 = Seeded.unit(i, 20 + w)
                        let u3 = Seeded.unit(i, 30 + w)
                        let u4 = Seeded.unit(i, 40 + w)
                        let origin = CGPoint(
                            x: top.x + (u1 - 0.5) * spread, y: top.y + u2 * 10 * unit)
                        let start = u3 * 0.45
                        let local = min(1, max(0, (state.formed - start) / 0.55))
                        let e = local * local * (3 - 2 * local)
                        guard e > 0 else { continue }
                        var p = CGPoint(
                            x: origin.x + (centre.x + target.x - origin.x) * e
                                + sin(e * .pi) * (u4 - 0.5) * 40 * unit,
                            y: origin.y + (centre.y + target.y - origin.y) * e)
                        var opacity = 0.3 + 0.7 * e
                        if state.gone > 0 {
                            let g = min(1, max(0, (state.gone - u4 * 0.3) / 0.7))
                            p.x += (u1 - 0.5) * 50 * g * unit
                            p.y -= (20 + 40 * u2) * g * unit
                            opacity *= 1 - g
                        }
                        let r = fontSize * 0.036 * (0.8 + 0.4 * u2) * (e < 1 ? 0.8 : 1)
                        canvas.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                            with: .color(.ariBone.opacity(opacity)))
                    }
                }
            }
        }
    }

    /// The Desk's dreaming overlay: thoughts rising off Kumo into the space above it.
    struct DriftOverlay: View {
        let stage: DriftStage
        var scale: CGFloat = 1

        var body: some View {
            DriftField(
                words: words, kumoCenter: { CGPoint(x: $0.width / 2, y: $0.height - 51) },
                kumoSize: 150, wordCenter: { CGPoint(x: $0.width / 2, y: $0.height - 172) },
                fontSize: 54,
                loose: stage == .drifting ? 46 : 26,
                time: stage == .drifting ? 0.1 : stage == .word ? 0.45 : 0.8)
        }

        private var words: [WordState] {
            switch stage {
            case .drifting: [WordState(word: "Leo", formed: 0.32)]
            case .word: [WordState(word: "Leo", formed: 1)]
            case .nextWord:
                [WordState(word: "Leo", formed: 1, gone: 1), WordState(word: "rain", formed: 0.86)]
            }
        }
    }

    // MARK: - Watching the dream

    /// Tapping sleeping Kumo while it dreams: a closer look, the word it's on, a line on what
    /// that means, and the words before it, fading.
    struct SleepWatchScreen: View {
        var body: some View {
            ZStack {
                SketchDayLight(hour: 4.3).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dreaming").font(.ariHeading).foregroundStyle(.ariText)
                            Text("04:17 · since 04:00").font(.footnote).foregroundStyle(
                                .ariTertiary)
                        }
                        Spacer()
                        RoundGlass(symbol: "xmark")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 10) {
                        earlier("Leo", "two pages made one")
                        earlier("rain", "your run moved to 07:30")
                        earlier("Monday", "your journal, written")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 34)
                    Spacer()
                    Text("Folding twelve notes into Northwind's page.")
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(.ariSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    SleepingKumo(size: 200, settling: 1)
                        .padding(.top, 36)
                        .padding(.bottom, 70)
                }
                DriftField(
                    words: [WordState(word: "Northwind", formed: 0.97)],
                    kumoCenter: { CGPoint(x: $0.width / 2, y: $0.height - 70 - 92) },
                    kumoSize: 200,
                    wordCenter: { CGPoint(x: $0.width / 2, y: $0.height * 0.43) },
                    fontSize: 62, loose: 40, time: 0.55
                )
                .allowsHitTesting(false)
            }
            .background(Color.ariBackground)
        }

        private func earlier(_ word: String, _ meaning: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(.ariSecondary)
                Text(meaning).font(.footnote).foregroundStyle(.ariTertiary)
            }
            .opacity(0.8)
        }
    }

    /// A round glass button, as Ito's sheets have.
    struct RoundGlass: View {
        let symbol: String
        var side: CGFloat = 40

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: side * 0.38, weight: .semibold))
                .foregroundStyle(.ariText)
                .frame(width: side, height: side)
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }

    // MARK: - Weaving the day

    enum WeaveStage { case gathering, knotting, tomorrow }

    /// The day's conversations as dotted strands, each in its own rhythm, coming in from the
    /// left; Kumo, the loom, ties them into knots that become pages, and spins one strand on to
    /// the right: tomorrow, with its plans as knots.
    struct WeaveCanvas: View {
        let stage: WeaveStage
        var compact = false

        static let strands = [
            "Main chat", "Northwind prep", "Shoes", "Mira's birthday", "Mail · 6 you read",
            "Run · 8 km, slow",
        ]

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                let loom = CGPoint(x: size.width * 0.40, y: size.height * 0.5)
                ZStack(alignment: .topLeading) {
                    Canvas { canvas, size in draw(in: canvas, size: size) }
                    if !compact {
                        ForEach(Array(Self.strands.enumerated()), id: \.offset) { i, name in
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.ariTertiary)
                                .fixedSize()
                                .offset(x: 6, y: start(i, size).y + (i < 3 ? -24 : 8))
                        }
                    }
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                        let p = pagePoint(i, size)
                        Text(
                            stage == .tomorrow && !compact
                                ? page.made : compact ? page.short : page.word
                        )
                        .font(compact ? .system(size: 9) : .caption2)
                        .foregroundStyle(stage == .tomorrow ? Color.ariSecondary : .ariTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .position(x: p.x, y: p.y + (compact ? 20 : 30))
                        .opacity(stage == .gathering ? 0 : 1)
                    }
                    if stage == .tomorrow {
                        ForEach(Array(plans.enumerated()), id: \.offset) { i, plan in
                            let p = planPoint(i, size)
                            VStack(spacing: 1) {
                                Text(plan.time).monospacedDigit().foregroundStyle(.ariTertiary)
                                if !compact { Text(plan.title).foregroundStyle(.ariSecondary) }
                            }
                            .font(compact ? .system(size: 9) : .caption2)
                            .fixedSize()
                            .position(x: p.x, y: p.y + (i == 1 ? -24 : 24) * (compact ? 0.8 : 1))
                        }
                        Text(compact ? "" : "Tuesday")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.ariTertiary)
                            .fixedSize()
                            .position(x: size.width - 30, y: tomorrowEnd(size).y - 16)
                    }
                    KumoFace(mood: .focused, size: compact ? 52 : 86)
                        .position(loom)
                }
            }
        }

        private struct PageMark {
            let word: String
            let made: String
            let short: String
        }

        private var pages: [PageMark] {
            [
                PageMark(word: "Leo", made: "Leo\none page now", short: "Leo"),
                PageMark(word: "Northwind", made: "Northwind\n12 notes in", short: "Northwind"),
                PageMark(word: "Monday", made: "Journal\nMonday", short: "Journal"),
            ]
        }

        private var plans: [SketchEvent] {
            [
                SketchEvent(start: 7.5, length: 0.75, title: "Run with Leo"),
                SketchEvent(start: 11, length: 0.5, title: "Halcyon prep"),
                SketchEvent(start: 14, length: 1, title: "Northwind"),
            ]
        }

        private func start(_ i: Int, _ size: CGSize) -> CGPoint {
            CGPoint(x: -4, y: size.height * (0.13 + 0.15 * Double(i)))
        }

        private func pagePoint(_ i: Int, _ size: CGSize) -> CGPoint {
            let spots = [(0.62, 0.15), (0.86, 0.22), (0.72, 0.33)]
            return CGPoint(x: size.width * spots[i].0, y: size.height * spots[i].1)
        }

        private func planPoint(_ i: Int, _ size: CGSize) -> CGPoint {
            let xs = [0.61, 0.75, 0.89]
            let x = size.width * xs[i]
            return CGPoint(x: x, y: tomorrowY(x, size))
        }

        private func tomorrowEnd(_ size: CGSize) -> CGPoint {
            CGPoint(x: size.width + 4, y: size.height * 0.72)
        }

        /// The tomorrow strand's height at x, read off its curve.
        private func tomorrowY(_ x: CGFloat, _ size: CGSize) -> CGFloat {
            let curve = tomorrowCurve(size)
            var best = curve.0
            var bestDistance = CGFloat.infinity
            for k in 0...200 {
                let p = Self.bezier(curve, Double(k) / 200)
                if abs(p.x - x) < bestDistance {
                    bestDistance = abs(p.x - x)
                    best = p
                }
            }
            return best.y
        }

        private func tomorrowCurve(_ size: CGSize) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
            let loom = CGPoint(x: size.width * 0.40, y: size.height * 0.5)
            let from = CGPoint(x: loom.x + 30, y: loom.y + 10)
            let to = tomorrowEnd(size)
            return (
                from, CGPoint(x: from.x + 40, y: to.y), CGPoint(x: to.x - 120, y: to.y), to
            )
        }

        static func bezier(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: Double) -> CGPoint {
            let u = 1 - t
            let a = u * u * u
            let b = 3 * u * u * t
            let cc = 3 * u * t * t
            let d = t * t * t
            return CGPoint(
                x: a * c.0.x + b * c.1.x + cc * c.2.x + d * c.3.x,
                y: a * c.0.y + b * c.1.y + cc * c.2.y + d * c.3.y)
        }

        /// Dots along a curve, up to `drawn` of its length, in a rhythm: gaps between dots, and
        /// their radii, repeating. Returns the head, where it stopped.
        @discardableResult
        private func strand(
            _ canvas: GraphicsContext, _ curve: (CGPoint, CGPoint, CGPoint, CGPoint),
            drawn: Double, gaps: [CGFloat], radii: [CGFloat], colour: Color
        ) -> CGPoint {
            var samples: [CGPoint] = []
            for k in 0...240 { samples.append(Self.bezier(curve, Double(k) / 240)) }
            var total: CGFloat = 0
            for k in 1..<samples.count {
                total += hypot(samples[k].x - samples[k - 1].x, samples[k].y - samples[k - 1].y)
            }
            let limit = total * drawn
            var path = Path()
            var travelled: CGFloat = 0
            var nextAt: CGFloat = 0
            var n = 0
            var head = samples[0]
            for k in 1..<samples.count {
                let a = samples[k - 1]
                let b = samples[k]
                let length = hypot(b.x - a.x, b.y - a.y)
                while nextAt <= travelled + length, nextAt <= limit {
                    let f = length > 0 ? (nextAt - travelled) / length : 0
                    let p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                    let r = radii[n % radii.count] * (compact ? 0.75 : 1)
                    path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    head = p
                    nextAt += gaps[n % gaps.count] * (compact ? 0.8 : 1)
                    n += 1
                }
                travelled += length
            }
            canvas.fill(path, with: .color(colour))
            return head
        }

        private func draw(in canvas: GraphicsContext, size: CGSize) {
            let loom = CGPoint(x: size.width * 0.40, y: size.height * 0.5)
            let rhythms: [([CGFloat], [CGFloat])] = [
                ([4], [1.1]),
                ([3, 3, 8], [1.3]),
                ([6], [1.6, 0.9]),
                ([3.4], [0.9]),
                ([2.6, 2.6, 2.6, 9], [1.0]),
                ([5, 9], [1.4]),
            ]
            let drawn = stage == .gathering ? 0.62 : 1
            for i in 0..<Self.strands.count {
                let s = start(i, size)
                let e = CGPoint(x: loom.x - 24, y: loom.y + (Double(i) - 2.5) * 5)
                let curve = (
                    s, CGPoint(x: size.width * 0.22, y: s.y),
                    CGPoint(x: size.width * 0.27, y: e.y + (s.y - loom.y) * 0.22), e
                )
                let opacity = 0.5 + 0.08 * Double(i % 3)
                let head = strand(
                    canvas, curve, drawn: drawn, gaps: rhythms[i].0, radii: rhythms[i].1,
                    colour: .ariBone.opacity(opacity))
                if stage == .gathering {
                    let r: CGFloat = 2.6
                    canvas.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)),
                        with: .color(.ariBone))
                }
            }
            guard stage != .gathering else { return }
            // Out of the loom: a strand to each page, a knot where it ties.
            for i in 0..<3 {
                let p = pagePoint(i, size)
                let from = CGPoint(x: loom.x + 22, y: loom.y - 14)
                let curve = (
                    from, CGPoint(x: from.x + 30, y: from.y - 10),
                    CGPoint(x: p.x - 40, y: p.y + 30), p
                )
                strand(
                    canvas, curve, drawn: stage == .knotting ? 0.92 : 1, gaps: [3.6], radii: [0.9],
                    colour: .ariBone.opacity(0.5))
                if stage == .knotting {
                    knot(canvas, p, tight: Double(i) * 0.3)
                } else {
                    pageMark(canvas, p)
                }
            }
            // Tomorrow.
            let curve = tomorrowCurve(size)
            strand(
                canvas, curve, drawn: stage == .knotting ? 0.28 : 1, gaps: [4, 4, 10],
                radii: [1.5], colour: .ariBone.opacity(0.75))
            if stage == .tomorrow {
                for i in 0..<3 {
                    let p = planPoint(i, size)
                    var k = Path()
                    for dx in stride(from: -6.0, through: 6.0, by: 4.0) {
                        let r: CGFloat = compact ? 1.8 : 2.4
                        k.addEllipse(
                            in: CGRect(x: p.x + dx - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    }
                    canvas.fill(k, with: .color(.ariText))
                }
            }
        }

        /// A knot: a little coil of dots, pulling tight.
        private func knot(_ canvas: GraphicsContext, _ c: CGPoint, tight: Double) {
            var coil = Path()
            for k in 0..<14 {
                let a = Double(k) * 0.9
                let r = (compact ? 5 : 8) * (1 - Double(k) / 18) * (1 - 0.3 * tight)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.8)
                let s = 1.3 - Double(k) * 0.03
                coil.addEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
            }
            canvas.fill(coil, with: .color(.ariBone.opacity(0.9)))
        }

        /// A page: a small dotted leaf with lines of writing.
        private func pageMark(_ canvas: GraphicsContext, _ c: CGPoint) {
            let w: CGFloat = compact ? 16 : 24
            let h: CGFloat = compact ? 20 : 30
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            canvas.fill(
                Path(roundedRect: rect, cornerRadius: 3), with: .color(.ariBone.opacity(0.12)))
            canvas.stroke(
                Path(roundedRect: rect, cornerRadius: 3), with: .color(.ariBone.opacity(0.7)),
                lineWidth: 1)
            var lines = Path()
            for row in 0..<4 {
                let y = rect.minY + h * 0.25 + CGFloat(row) * h * 0.16
                for x in stride(
                    from: rect.minX + w * 0.2, through: rect.maxX - w * (row == 3 ? 0.45 : 0.2),
                    by: compact ? 2.4 : 3.2)
                {
                    lines.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                }
            }
            canvas.fill(lines, with: .color(.ariBone.opacity(0.8)))
        }
    }

    /// The dream, live: weaving the day, full screen, with a line on what Kumo is doing.
    struct WeaveScreen: View {
        let stage: WeaveStage

        var body: some View {
            ZStack {
                SketchDayLight(hour: 4.1).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dreaming").font(.ariHeading).foregroundStyle(.ariText)
                            Text(subtitle).font(.footnote).foregroundStyle(.ariTertiary)
                        }
                        Spacer()
                        RoundGlass(symbol: "xmark")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    WeaveCanvas(stage: stage)
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                    Text(caption)
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(.ariSecondary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 36)
                        .frame(height: 90, alignment: .top)
                    PhaseDots(stage: stage)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 26)
                }
            }
            .background(Color.ariBackground)
        }

        private var subtitle: String {
            switch stage {
            case .gathering: "04:03 · weaving Monday"
            case .knotting: "04:11 · weaving Monday"
            case .tomorrow: "04:24 · weaving Monday"
            }
        }

        private var caption: String {
            switch stage {
            case .gathering: "Gathering Monday: nine threads, six emails you read, a slow 8 km."
            case .knotting: "Leo had two pages. Tying them into one."
            case .tomorrow: "Rain from eight tomorrow, so your run moves to 07:30."
            }
        }
    }

    /// Where the dream is: gathering, tying, tomorrow, as three dots on a short thread.
    struct PhaseDots: View {
        let stage: WeaveStage

        var body: some View {
            let at = stage == .gathering ? 0 : stage == .knotting ? 1 : 2
            HStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(i <= at ? Color.ariText : .ariLine)
                            .frame(width: i == at ? 8 : 6, height: i == at ? 8 : 6)
                        Text(["Gathering", "Tying", "Tomorrow"][i])
                            .font(.caption2)
                            .foregroundStyle(i == at ? Color.ariSecondary : .ariTertiary)
                    }
                }
            }
        }
    }
#endif
