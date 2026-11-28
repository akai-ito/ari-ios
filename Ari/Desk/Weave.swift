import AriKit
import SwiftUI

/// Kumo's dream as a weave: the day's conversations come in from the left as dotted strands, each in
/// its own rhythm; Kumo in the middle is the loom; out of it come strands that tie into knots and
/// then become pages; and one strand spins on to the right, tomorrow, with its plans as knots.
///
/// `progress` runs from 0 to 3: gathering (0 to 1), tying (1 to 2) and tomorrow (2 to 3). `time`
/// keeps the knots alive while Kumo is still tying. The curves are worked out once per size, so a
/// frame only places dots.
struct WeaveCanvas: View {
    let scene: WeaveScene
    let progress: Double
    var time: Double = 0
    /// Small, as the morning strip: no strand names, smaller dots, short labels.
    var compact = false
    /// At rest, as the strip is until it replays: Kumo at the loom holds still too.
    var resting = false

    @State private var geometry = WeaveGeometry()

    var body: some View {
        Canvas { canvas, size in
            let shape = geometry.shape(for: scene, size: size, compact: compact)
            draw(shape, in: canvas, size: size)
        }
        .overlay {
            GeometryReader { proxy in
                // Nothing to animate on a page that's only being read.
                KumoFace(mood: .focused, size: compact ? 50 : 86, still: resting)
                    .position(x: proxy.size.width * 0.40, y: proxy.size.height * 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private func draw(_ shape: WeaveGeometry.Shape, in canvas: GraphicsContext, size: CGSize) {
        let p = progress
        let scale: CGFloat = compact ? 0.75 : 1
        // Gathering: the strands come in from the left, a bright dot at each head.
        let drawn = Ease.inOut(min(1, p / 1.25))
        for (i, strand) in shape.strands.enumerated() {
            let rhythm = Self.rhythms[i % Self.rhythms.count]
            let head = strand.dots(
                upTo: drawn, gaps: rhythm.gaps.map { $0 * scale },
                radii: rhythm.radii.map { $0 * scale },
                into: canvas, colour: .ariBone.opacity(0.5 + 0.08 * Double(i % 3)))
            if drawn < 1, let head {
                let r: CGFloat = 2.6 * scale
                canvas.fill(
                    Path(
                        ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)
                    ),
                    with: .color(.ariBone))
            }
            if !compact {
                let fade = min(1, p * 3)
                let label = Text(scene.strands[i]).font(.caption2).foregroundStyle(
                    Color.ariTertiary.opacity(fade))
                canvas.draw(
                    label, at: CGPoint(x: 6, y: strand.start.y + (strand.labelAbove ? -14 : 14)),
                    anchor: .leading)
            }
        }

        // Tying: a strand to each page, a knot pulling tight where it ties, then the page.
        let out = Ease.inOut(min(1, max(0, (p - 1.05) / 0.8)))
        let paged = min(1, max(0, (p - 2.05) / 0.4))
        for (i, strand) in shape.pages.enumerated() {
            strand.curve.dots(
                upTo: out, gaps: [3.6 * scale], radii: [0.9 * scale], into: canvas,
                colour: .ariBone.opacity(0.5))
            guard out > 0.85 else { continue }
            let tied = min(1, (out - 0.85) / 0.15)
            if paged < 1 {
                knot(
                    canvas, strand.end, tightness: tied, spin: time * 0.6 + Double(i),
                    opacity: 1 - paged)
            }
            if paged > 0 { pageMark(canvas, strand.end, opacity: paged) }
            let page = i < scene.pages.count ? scene.pages[i] : nil
            if let page {
                let words =
                    paged > 0.5 && !compact
                    ? [page.word, page.note].compactMap { $0 } : [page.word]
                let label = Text(words.joined(separator: "\n"))
                    .font(compact ? .system(size: 9) : .caption2)
                    .foregroundStyle(
                        (paged > 0.5 ? Color.ariSecondary : .ariTertiary).opacity(tied))
                canvas.draw(
                    label, at: CGPoint(x: strand.end.x, y: strand.end.y + (compact ? 14 : 20)),
                    anchor: .top)
            }
        }

        // Tomorrow: the strand it spins out to the right, with its plans as knots.
        let spun = Ease.inOut(min(1, max(0, (p - 1.6) / 1.25)))
        let head = shape.tomorrow.dots(
            upTo: spun, gaps: [4 * scale, 4 * scale, 10 * scale], radii: [1.5 * scale],
            into: canvas, colour: .ariBone.opacity(0.75))
        let reached = head?.x ?? -.infinity
        for (i, plan) in shape.plans.enumerated() where plan.x <= reached + 1 {
            var knot = Path()
            let r: CGFloat = compact ? 1.8 : 2.4
            for dx in stride(from: -6.0, through: 6.0, by: 4.0) {
                knot.addEllipse(
                    in: CGRect(x: plan.x + dx - r, y: plan.y - r, width: 2 * r, height: 2 * r))
            }
            canvas.fill(knot, with: .color(.ariText))
            guard i < scene.plans.count else { continue }
            let item = scene.plans[i]
            let time = Text(item.at, format: DeskTime.time).monospacedDigit().foregroundStyle(
                Color.ariTertiary)
            let label =
                compact
                ? time
                : Text(
                    "\(time)\n\(Text(Self.short(item.title)).foregroundStyle(Color.ariSecondary))")
            let above = i.isMultiple(of: 2) == false
            canvas.draw(
                label.font(compact ? .system(size: 9) : .caption2),
                at: CGPoint(x: plan.x, y: plan.y + (above ? -10 : 10)),
                anchor: above ? .bottom : .top)
        }
        if spun >= 1, !compact, let end = shape.tomorrow.samples.last {
            let label = Text(Self.tomorrowName(after: scene.day)).font(.caption2.weight(.semibold))
                .foregroundStyle(Color.ariTertiary)
            canvas.draw(label, at: CGPoint(x: end.x - 12, y: end.y + 12), anchor: .topTrailing)
        }
    }

    /// A knot: a little coil of dots, pulling tight and turning slowly.
    private func knot(
        _ canvas: GraphicsContext, _ c: CGPoint, tightness: Double, spin: Double, opacity: Double
    ) {
        var coil = Path()
        for k in 0..<14 {
            let a = Double(k) * 0.9 + spin
            let r = (compact ? 5 : 8) * (1 - Double(k) / 18) * (1 - 0.3 * tightness)
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.8)
            let s = (compact ? 1.0 : 1.3) - Double(k) * 0.03
            coil.addEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
        }
        canvas.fill(coil, with: .color(.ariBone.opacity(0.9 * opacity * tightness)))
    }

    /// A page: a small leaf with dotted lines of writing.
    private func pageMark(_ canvas: GraphicsContext, _ c: CGPoint, opacity: Double) {
        let w: CGFloat = compact ? 16 : 24
        let h: CGFloat = compact ? 20 : 30
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        canvas.fill(
            Path(roundedRect: rect, cornerRadius: 3), with: .color(.ariBone.opacity(0.12 * opacity))
        )
        canvas.stroke(
            Path(roundedRect: rect, cornerRadius: 3), with: .color(.ariBone.opacity(0.7 * opacity)),
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
        canvas.fill(lines, with: .color(.ariBone.opacity(0.8 * opacity)))
    }

    /// Each strand's rhythm: the gaps between its dots and their sizes, repeating.
    private static let rhythms: [(gaps: [CGFloat], radii: [CGFloat])] = [
        ([4], [1.1]), ([3, 3, 8], [1.3]), ([6], [1.6, 0.9]), ([3.4], [0.9]),
        ([2.6, 2.6, 2.6, 9], [1.0]), ([5, 9], [1.4]),
    ]

    /// A plan's title short enough to sit under its knot: "Prep for Halcyon…".
    static func short(_ title: String, limit: Int = 18) -> String {
        guard title.count > limit else { return title }
        var kept = ""
        for word in title.split(separator: " ") {
            let next = kept.isEmpty ? String(word) : "\(kept) \(word)"
            if next.count > limit { break }
            kept = next
        }
        return (kept.isEmpty ? String(title.prefix(limit)) : kept)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + "…"
    }

    /// "Tuesday" after "Monday".
    static func tomorrowName(after day: String) -> String {
        let names = Calendar.current.weekdaySymbols
        guard let index = names.firstIndex(of: day) else { return "Tomorrow" }
        return names[(index + 1) % 7]
    }
}

/// The weave's curves for one scene and size, worked out once and kept: each a run of points with
/// the distance along it, so placing dots is a walk, not a solve.
@MainActor
final class WeaveGeometry {
    struct Curve {
        let samples: [CGPoint]
        let lengths: [CGFloat]
        var start: CGPoint { samples.first ?? .zero }
        var total: CGFloat { lengths.last ?? 0 }

        init(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), count: Int = 120) {
            var samples: [CGPoint] = []
            var lengths: [CGFloat] = []
            var total: CGFloat = 0
            for k in 0...count {
                let p = Self.bezier(c, Double(k) / Double(count))
                if let last = samples.last { total += hypot(p.x - last.x, p.y - last.y) }
                samples.append(p)
                lengths.append(total)
            }
            self.samples = samples
            self.lengths = lengths
        }

        /// Dots along the curve up to `drawn` of its length, in a rhythm. Returns the last one.
        @discardableResult
        func dots(
            upTo drawn: Double, gaps: [CGFloat], radii: [CGFloat], into canvas: GraphicsContext,
            colour: Color
        ) -> CGPoint? {
            guard drawn > 0, samples.count > 1 else { return nil }
            let limit = total * drawn
            var path = Path()
            var at: CGFloat = 0
            var segment = 1
            var n = 0
            var head: CGPoint?
            while at <= limit {
                while segment < lengths.count - 1, lengths[segment] < at { segment += 1 }
                let a = samples[segment - 1]
                let b = samples[segment]
                let span = lengths[segment] - lengths[segment - 1]
                let f = span > 0 ? (at - lengths[segment - 1]) / span : 0
                let p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                let r = radii[n % radii.count]
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                head = p
                at += max(1, gaps[n % gaps.count])
                n += 1
            }
            canvas.fill(path, with: .color(colour))
            return head
        }

        /// The curve's height at x, read off its points.
        func y(at x: CGFloat) -> CGFloat {
            samples.min { abs($0.x - x) < abs($1.x - x) }?.y ?? 0
        }

        static func bezier(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: Double) -> CGPoint {
            let u = 1 - t
            let a = u * u * u
            let b = 3 * u * u * t
            let d = 3 * u * t * t
            let e = t * t * t
            return CGPoint(
                x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x,
                y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
        }
    }

    struct Strand {
        let curve: Curve
        let labelAbove: Bool
        var start: CGPoint { curve.start }

        func dots(
            upTo drawn: Double, gaps: [CGFloat], radii: [CGFloat], into canvas: GraphicsContext,
            colour: Color
        ) -> CGPoint? {
            curve.dots(upTo: drawn, gaps: gaps, radii: radii, into: canvas, colour: colour)
        }
    }

    struct PageStrand {
        let curve: Curve
        let end: CGPoint
    }

    struct Shape {
        let strands: [Strand]
        let pages: [PageStrand]
        let tomorrow: Curve
        let plans: [CGPoint]
    }

    private var key: String?
    private var kept: Shape?

    func shape(for scene: WeaveScene, size: CGSize, compact: Bool) -> Shape {
        let key =
            "\(Int(size.width))x\(Int(size.height)) \(scene.strands.count) \(scene.pages.count) \(scene.plans.count) \(compact)"
        if key == self.key, let kept { return kept }
        let shape = Self.make(scene, size: size)
        self.key = key
        kept = shape
        return shape
    }

    private static func make(_ scene: WeaveScene, size: CGSize) -> Shape {
        let w = size.width
        let h = size.height
        let loom = CGPoint(x: w * 0.40, y: h * 0.5)
        let count = max(1, scene.strands.count)
        let strands = (0..<count).map { i -> Strand in
            let y = count == 1 ? h * 0.5 : h * (0.13 + 0.75 * Double(i) / Double(count - 1))
            let s = CGPoint(x: -4, y: y)
            let e = CGPoint(x: loom.x - 24, y: loom.y + (Double(i) - Double(count - 1) / 2) * 5)
            let curve = Curve(
                (
                    s, CGPoint(x: w * 0.22, y: s.y),
                    CGPoint(x: w * 0.27, y: e.y + (s.y - loom.y) * 0.22), e
                ))
            return Strand(curve: curve, labelAbove: Double(i) < Double(count) / 2)
        }
        let spots = [(0.62, 0.15), (0.86, 0.22), (0.72, 0.33)]
        // Three knots while Kumo is still tying, even before it can say what they are.
        let pageCount = scene.isRecorded ? scene.pages.count : 3
        let pages = (0..<min(3, pageCount)).map { i -> PageStrand in
            let p = CGPoint(x: w * spots[i].0, y: h * spots[i].1)
            let from = CGPoint(x: loom.x + 22, y: loom.y - 14)
            let curve = Curve(
                (
                    from, CGPoint(x: from.x + 30, y: from.y - 10),
                    CGPoint(x: p.x - 40, y: p.y + 30), p
                ),
                count: 60)
            return PageStrand(curve: curve, end: p)
        }
        let from = CGPoint(x: loom.x + 30, y: loom.y + 10)
        let to = CGPoint(x: w + 4, y: h * 0.72)
        let tomorrow = Curve(
            (from, CGPoint(x: from.x + 40, y: to.y), CGPoint(x: to.x - 120, y: to.y), to))
        let xs = [0.61, 0.75, 0.89]
        let plans = (0..<min(3, scene.plans.count)).map { i -> CGPoint in
            let x = w * xs[i]
            return CGPoint(x: x, y: tomorrow.y(at: x))
        }
        return Shape(strands: strands, pages: pages, tomorrow: tomorrow, plans: plans)
    }
}

/// Where the dream is: gathering, tying, tomorrow, as three dots.
struct WeavePhaseDots: View {
    let progress: Double

    var body: some View {
        let at = min(2, Int(progress))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Gathering the day", "Tying it together", "Tomorrow"][at])
    }
}

/// How the weave plays: through once in a set time, as a replay; or live, gathering, then tying for
/// as long as Kumo dreams, then on to tomorrow once its record comes.
struct WeaveClock {
    enum Mode: Equatable {
        case replay(seconds: Double)
        case live
    }

    let mode: Mode
    let started: Date
    /// When the record came, for a live weave.
    var recorded: Date?
    /// Where the live weave had got to when the record came.
    var recordedFrom: Double = 1.9

    /// Where the weave is at a moment.
    func progress(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(started)
        switch mode {
        case .replay(let seconds):
            return min(3, max(0, elapsed / seconds * 3))
        case .live:
            // Gathering takes nine seconds, then it ties until the record comes.
            let tying = min(1.9, elapsed / 9 * 1.3 + max(0, elapsed - 9) * 0.05)
            guard let recorded else { return tying }
            let after = now.timeIntervalSince(recorded)
            return min(3, recordedFrom + after / 6 * (3 - recordedFrom))
        }
    }

    /// Whether it has nothing left to move.
    func isDone(at now: Date) -> Bool { progress(at: now) >= 3 }

    /// The line for a moment: what it gathered, each thing it tied, then each plan for tomorrow.
    static func caption(_ scene: WeaveScene, progress: Double, time: Double) -> String {
        if progress < 1.05 { return scene.gathering }
        let lines = progress < 2.05 ? scene.tying : scene.tomorrow
        guard !lines.isEmpty else { return scene.gathering }
        let phase = progress < 2.05 ? progress - 1.05 : progress - 2.05
        // Through a recorded phase by progress; while tying live, a line every few seconds.
        let index =
            scene.isRecorded
            ? min(lines.count - 1, Int(phase * Double(lines.count)))
            : Int(time / 4) % lines.count
        return lines[index]
    }
}
