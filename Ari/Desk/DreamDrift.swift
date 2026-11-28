import AriKit
import CoreText
import SwiftUI
import UIKit

/// Kumo asleep on its cushion, as the Desk shows it at night: dusky, sparse dots, eyes shut in two
/// soft arcs, breathing slowly, with z's drifting off it until it dreams. While it dreams the top of
/// the pebble thins, as if its thoughts lift off. It redraws a few times a second at most, and holds
/// still under Reduce Motion.
struct SleepingKumo: View {
    var size: CGFloat = 150
    /// Whether it's dreaming: its top thins.
    var dreaming = false
    /// Whether z's drift off it.
    var zs = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: size, height: size * 0.92)
            .overlay {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
                    Canvas { canvas, area in
                        draw(
                            in: &canvas, area: area,
                            t: reduceMotion ? 1 : context.date.timeIntervalSinceReferenceDate)
                    }
                }
                .frame(width: size * 1.9, height: size * 1.7)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, area: CGSize, t: Double) {
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

        if zs, !dreaming { drawZs(in: canvas, t: t) }

        let breath = sin(t * 2 * .pi / 8)
        canvas.translateBy(x: 0, y: 1.2 - 0.5 * breath)
        canvas.rotate(by: .degrees(5))
        canvas.scaleBy(x: 1 - 0.012 * breath, y: 1 + 0.03 * breath)
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
                if dreaming, y < -9 {
                    let seed = Seeded.unit(Int(x * 10 + y * 100), 3)
                    r *= 1 - 0.4 * (0.5 + 0.5 * sin(t * 0.8 + seed * 9))
                }
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
        let fill = Color.ariDusk.mix(with: .ariBone, by: 0.42).mix(with: SkyGlyph.lamp, by: 0.05)
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

    /// Two z's in dots, rising and fading off the upper right.
    private func drawZs(in canvas: GraphicsContext, t: Double) {
        for i in 0..<2 {
            let phase = (t / 6 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
            let opacity = sin(phase * .pi) * 0.75
            let s = 0.7 + 0.5 * phase
            let o = CGPoint(x: 19 + 7 * phase, y: -12 - 12 * phase)
            let z: [(Double, Double)] = [
                (-2, -2), (0, -2), (2, -2), (0.7, -0.7), (-0.7, 0.7), (-2, 2), (0, 2), (2, 2),
            ]
            var dots = Path()
            let r = (1.1 * s + 0.2) / 2
            for (dx, dy) in z {
                dots.addEllipse(
                    in: CGRect(
                        x: o.x + dx * s - r, y: o.y + dy * s - r, width: 2 * r, height: 2 * r))
            }
            canvas.fill(dots, with: .color(.ariBone.opacity(opacity)))
        }
    }
}

/// Small numbers that look random but are the same every time, for where each dot starts.
enum Seeded {
    static func unit(_ index: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(index &* 7919 &+ salt &* 104_729))
        x ^= x >> 33
        x &*= 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x &*= 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - Words in dots

/// A word as dots on a halftone grid, filled where bold serif letters are: dense enough that each
/// stroke is two dots wide, so the word reads at a glance. Worked out once per word and size.
@MainActor
enum DotWord {
    private static var cache: [String: [CGPoint]] = [:]

    /// The dots, centred on zero, with y growing downward.
    static func points(_ word: String, size: CGFloat) -> [CGPoint] {
        let key = "\(word)@\(Int(size))"
        if let known = cache[key] { return known }
        let step = size * 0.068
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let font =
            base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) }
            ?? base
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
                if let glyph = CTFontCreatePathForGlyph(font as CTFont, glyphs[i], nil) {
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
        cache[key] = points
        return points
    }

    /// How wide the word is at a size, to fit it on the screen.
    static func width(_ word: String, size: CGFloat) -> CGFloat {
        let points = points(word, size: size)
        guard let low = points.map(\.x).min(), let high = points.map(\.x).max() else { return 0 }
        return high - low
    }
}

/// Thoughts drifting up off sleeping Kumo while it dreams, gathering for a few seconds into a word
/// above it, crisp and bone-white so it reads, then blowing away before the next. Kumo's top and the
/// words' centre are in its own space. Under Reduce Motion nothing moves: the word stands, and the
/// next takes its place with a fade.
struct DreamDrift: View {
    /// The words to form, one after another.
    let words: [String]
    /// Where Kumo's head is, in this view's space.
    let kumoTop: CGPoint
    /// Where the words form.
    let wordCentre: CGPoint
    var fontSize: CGFloat = 64
    var kumoSize: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long each word takes: forming, holding, blowing away, and a breath before the next.
    static let period = 8.0

    var body: some View {
        if reduceMotion {
            TimelineView(.periodic(from: .now, by: Self.period)) { context in
                let word = word(at: context.date.timeIntervalSinceReferenceDate)
                Canvas { canvas, size in
                    drawWord(word, formed: 1, gone: 0, in: canvas, size: size, salt: 0)
                }
                .id(word)
                .transition(.opacity)
                .animation(.easeInOut(duration: 1), value: word)
            }
            .accessibilityHidden(true)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                Canvas { canvas, size in
                    draw(in: canvas, size: size, t: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func word(at t: Double) -> String {
        guard !words.isEmpty else { return "" }
        return words[Int(t / Self.period) % words.count]
    }

    private func draw(in canvas: GraphicsContext, size: CGSize, t: Double) {
        let unit = kumoSize / 150
        // Loose thoughts rising off the top of Kumo.
        let spread = kumoSize * 0.55
        let rise = kumoTop.y - wordCentre.y + 50 * unit
        var loose = [Path](repeating: Path(), count: 4)
        for j in 0..<36 {
            let phase = (Seeded.unit(j, 1) + t * (0.05 + 0.05 * Seeded.unit(j, 2)))
                .truncatingRemainder(dividingBy: 1)
            let x =
                kumoTop.x + (Seeded.unit(j, 4) - 0.5) * spread
                + sin(phase * 6 + Seeded.unit(j, 5) * 10) * 9 * unit
            let y = kumoTop.y - phase * rise
            let r = (0.8 + 0.9 * Seeded.unit(j, 6)) * unit
            let level = min(3, Int(sin(phase * .pi) * 4))
            loose[level].addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        for (level, path) in loose.enumerated() {
            canvas.fill(path, with: .color(.ariBone.opacity(0.12 + 0.14 * Double(level))))
        }
        guard !words.isEmpty else { return }
        let index = Int(t / Self.period)
        let local = t.truncatingRemainder(dividingBy: Self.period)
        // 0–2.6 s forming, held to 5.8 s, blown away by 7.2 s.
        let formed = min(1, local / 2.6)
        let gone = max(0, min(1, (local - 5.8) / 1.4))
        drawWord(
            words[index % words.count], formed: formed, gone: gone, in: canvas, size: size,
            salt: index)
    }

    /// One word: each dot flies up from Kumo's head to its place in the letter, waits there, then
    /// blows away up and out. Fully formed, every dot sits exactly on its grid and is fully lit.
    private func drawWord(
        _ word: String, formed: Double, gone: Double, in canvas: GraphicsContext, size: CGSize,
        salt: Int
    ) {
        guard !word.isEmpty else { return }
        let unit = kumoSize / 150
        let fitting = min(
            fontSize, fontSize * (size.width - 64) / max(1, DotWord.width(word, size: fontSize)))
        let points = DotWord.points(word, size: fitting.rounded(.down))
        let step = fitting * 0.068
        let radius = step * 0.42
        var levels = [Path](repeating: Path(), count: 6)
        for (i, target) in points.enumerated() {
            let u1 = Seeded.unit(i, 10 + salt)
            let u2 = Seeded.unit(i, 20 + salt)
            let u3 = Seeded.unit(i, 30 + salt)
            let u4 = Seeded.unit(i, 40 + salt)
            let start = u3 * 0.4
            let local = min(1, max(0, (formed - start) / 0.6))
            let e = local * local * (3 - 2 * local)
            guard e > 0 else { continue }
            let origin = CGPoint(
                x: kumoTop.x + (u1 - 0.5) * kumoSize * 0.5, y: kumoTop.y + u2 * 8 * unit)
            let goal = CGPoint(x: wordCentre.x + target.x, y: wordCentre.y + target.y)
            var p = CGPoint(
                x: origin.x + (goal.x - origin.x) * e + sin(e * .pi) * (u4 - 0.5) * 46 * unit,
                y: origin.y + (goal.y - origin.y) * e)
            var opacity = 0.35 + 0.65 * e
            if gone > 0 {
                let g = min(1, max(0, (gone - u4 * 0.3) / 0.7))
                p.x += (u1 - 0.5) * 60 * g * unit + 30 * g * unit
                p.y -= (24 + 46 * u2) * g * unit
                opacity *= 1 - g
            }
            let r = radius * (e < 1 ? 0.85 : 1)
            let level = min(5, Int(opacity * 6))
            levels[level].addEllipse(
                in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        for (level, path) in levels.enumerated() where !path.isEmpty {
            canvas.fill(
                path, with: .color(.ariBone.opacity(level == 5 ? 1 : Double(level + 1) / 6)))
        }
    }
}
