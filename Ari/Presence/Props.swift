import SwiftUI

// The props Ari holds beside its pebble while it works, one per task: thought dots while thinking, a
// magnifying glass while searching the web, a page while reading, a prompt while running a command,
// a pencil while changing files, a checklist while planning, an hourglass while waiting, typed dots
// while writing, notes settling into a stack while tidying, and a question mark while it asks you.
// All in the pebble's own bone dots, in its coordinates (the pebble spans about ±18 by ±16).

extension Pose {
    /// Draws this pose's prop, if it has one, `since` seconds into the pose.
    func drawProp(in canvas: GraphicsContext, since t: Double, opacity: Double) {
        guard opacity > 0.01 else { return }
        var ink = PropInk(canvas: canvas, opacity: opacity)
        switch self {
        case .thinking: ThoughtProp.draw(&ink, t)
        case .webSearch: LensProp.draw(&ink, t)
        case .reading: PageProp.draw(&ink, t)
        case .running: PromptProp.draw(&ink, t)
        case .editing: PencilProp.draw(&ink, t)
        case .planning: ChecklistProp.draw(&ink, t)
        case .waiting: HourglassProp.draw(&ink, t)
        case .writing: TypedProp.draw(&ink, t)
        case .tidying: TidyProp.draw(&ink, t)
        case .asking: QuestionProp.draw(&ink, t)
        default: break
        }
    }
}

/// Dots, in bone, with a dark ring so a prop reads against the pebble's own dots.
struct PropInk {
    var canvas: GraphicsContext
    let opacity: Double

    func dot(_ x: Double, _ y: Double, _ size: Double = 1.7, _ shade: Double = 1) {
        guard shade > 0 else { return }
        let ring = size + 1.2
        canvas.fill(
            Path(ellipseIn: CGRect(x: x - ring / 2, y: y - ring / 2, width: ring, height: ring)),
            with: .color(Color.ariBackground.opacity(opacity * shade)))
        canvas.fill(
            Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
            with: .color(Color.ariBone.opacity(opacity * shade)))
    }

    /// Dots along a line, one every `step`.
    func line(
        from a: CGPoint, to b: CGPoint, step: Double = 2.4, size: Double = 1.5, shade: Double = 1
    ) {
        let length = hypot(b.x - a.x, b.y - a.y)
        let count = max(1, Int(length / step))
        for i in 0...count {
            let f = Double(i) / Double(count)
            dot(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, size, shade)
        }
    }

    /// Dots around a circle.
    func ring(_ c: CGPoint, radius: Double, count: Int, size: Double = 1.5, shade: Double = 1) {
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            dot(c.x + radius * cos(angle), c.y + radius * sin(angle), size, shade)
        }
    }
}

private func propEase(_ x: Double) -> Double {
    let x = min(1, max(0, x))
    return x * x * (3 - 2 * x)
}

// MARK: - The props

/// Three thought dots rising up and away to the right, one after another.
private enum ThoughtProp {
    static func draw(_ ink: inout PropInk, _ t: Double) {
        for i in 0..<3 {
            let phase = (t * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = 17 + 11 * phase
            let y = -13 - 14 * phase
            let size = 1.6 + 2.8 * phase
            let shade = sin(phase * .pi)
            ink.dot(x, y, size, shade)
        }
    }
}

/// A magnifying glass of dots, sweeping slowly back and forth in front of the pebble's lower right.
enum LensProp {
    static func position(_ t: Double) -> CGPoint {
        CGPoint(x: 29 + 3 * sin(t * 1.3), y: 2 + 2 * sin(t * 2.6))
    }

    fileprivate static func draw(_ ink: inout PropInk, _ t: Double) {
        let c = position(t)
        // A dark window, then a few dots magnified inside it, then the rim.
        let r = 7.2
        ink.canvas.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(Color.ariBackground.opacity(ink.opacity)))
        let drift = 1.2 * sin(t * 1.3)
        for (dx, dy) in [(-2.6, -2.2), (2.2, -2.6), (-0.2, 1.6), (3.4, 2.4), (-3.6, 2.8)] {
            ink.dot(c.x + dx + drift, c.y + dy, 2.9, 0.75)
        }
        ink.ring(c, radius: r, count: 18, size: 1.7)
        // The handle, down and to the right.
        ink.line(
            from: CGPoint(x: c.x + 5.9, y: c.y + 5.9), to: CGPoint(x: c.x + 10.6, y: c.y + 10.6),
            step: 2.2, size: 2.2)
    }
}

/// A page of dots beside the pebble, its lines lighting up one by one as Ari reads them.
enum PageProp {
    static let lines = 4

    static func line(_ t: Double) -> (index: Int, progress: Double) {
        let cycle = (t * 0.8).truncatingRemainder(dividingBy: Double(lines))
        return (Int(cycle), cycle - floor(cycle))
    }

    fileprivate static func draw(_ ink: inout PropInk, _ t: Double) {
        let left = 23.0
        let top = -10.0
        let width = 13.0
        let height = 18.0
        // The page's corners and edges, sparsely.
        ink.line(
            from: CGPoint(x: left, y: top), to: CGPoint(x: left + width, y: top), step: 2.75,
            size: 1.1, shade: 0.55)
        ink.line(
            from: CGPoint(x: left, y: top + height), to: CGPoint(x: left + width, y: top + height),
            step: 2.75, size: 1.1, shade: 0.55)
        ink.line(
            from: CGPoint(x: left, y: top), to: CGPoint(x: left, y: top + height), step: 3,
            size: 1.1, shade: 0.55)
        ink.line(
            from: CGPoint(x: left + width, y: top), to: CGPoint(x: left + width, y: top + height),
            step: 3, size: 1.1, shade: 0.55)
        let reading = line(t)
        for i in 0..<lines {
            let y = top + 3.6 + Double(i) * 3.6
            let length = i == lines - 1 ? 0.6 : 1.0
            let shade = i < reading.index ? 0.9 : i == reading.index ? 1 : 0.35
            let dots = Int(4 * length)
            for d in 0...dots {
                let x = left + 2.5 + Double(d) * 2.1
                let lit = i == reading.index ? (Double(d) / 4 <= reading.progress ? 1 : 0.3) : shade
                ink.dot(x, y, 1.6, lit)
            }
        }
    }
}

/// A prompt of dots, `>_`, with the cursor blinking.
private enum PromptProp {
    static func draw(_ ink: inout PropInk, _ t: Double) {
        let x = 24.0
        let y = 0.0
        // The chevron.
        ink.dot(x, y - 3.2, 1.6)
        ink.dot(x + 2, y - 1.6, 1.6)
        ink.dot(x + 4, y, 1.7)
        ink.dot(x + 2, y + 1.6, 1.6)
        ink.dot(x, y + 3.2, 1.6)
        // The cursor, blinking, with a run of output dots appearing now and then.
        let blink = (t * 1.6).truncatingRemainder(dividingBy: 1) < 0.55 ? 1.0 : 0.15
        ink.line(
            from: CGPoint(x: x + 7, y: y + 3.4), to: CGPoint(x: x + 12, y: y + 3.4), step: 1.7,
            size: 1.4, shade: blink)
        let output = (t * 0.7).truncatingRemainder(dividingBy: 1)
        for i in 0..<4 where Double(i) / 4 < output {
            ink.dot(x + Double(i) * 2.2, y + 8, 1.1, 0.6)
        }
    }
}

/// A pencil of dots laying down a line of dots, then lifting to start the next.
enum PencilProp {
    static func tip(_ t: Double) -> CGPoint {
        let stroke = (t * 0.5).truncatingRemainder(dividingBy: 1)
        return CGPoint(x: 23 + 13 * stroke, y: 9)
    }

    fileprivate static func draw(_ ink: inout PropInk, _ t: Double) {
        let stroke = (t * 0.5).truncatingRemainder(dividingBy: 1)
        let tip = tip(t)
        // The line it has written so far.
        var x = 23.0
        while x <= tip.x {
            ink.dot(x, 9 + 0.6 * sin(x * 1.3), 1.5, 0.9)
            x += 2.2
        }
        // The pencil itself: a slanted run of dots ending at the tip, lifting at the end.
        let lift = stroke > 0.88 ? (stroke - 0.88) * 18 : 0
        let end = CGPoint(x: tip.x, y: tip.y - 1.8 - lift)
        // The lead, small, then the pencil's body, thicker.
        ink.dot(end.x, end.y, 1.3)
        ink.line(
            from: CGPoint(x: end.x + 1.6, y: end.y - 2.4),
            to: CGPoint(x: end.x + 6.4, y: end.y - 11), step: 2.1, size: 2.3)
    }
}

/// A short checklist whose boxes tick one by one.
enum ChecklistProp {
    static func current(_ t: Double) -> Int { Int((t * 0.9).truncatingRemainder(dividingBy: 4)) }

    fileprivate static func draw(_ ink: inout PropInk, _ t: Double) {
        let done = current(t)
        for i in 0..<3 {
            let y = -7.0 + Double(i) * 6.5
            let x = 24.0
            if i < done {
                // A tick: a short stroke down, then a longer one up.
                ink.dot(x - 1.4, y, 1.5)
                ink.dot(x, y + 1.5, 1.6)
                ink.dot(x + 1.7, y - 0.5, 1.6)
                ink.dot(x + 3.2, y - 2.3, 1.5)
            } else {
                ink.ring(CGPoint(x: x + 0.8, y: y), radius: 2.1, count: 7, size: 1.1, shade: 0.6)
            }
            ink.line(
                from: CGPoint(x: x + 6, y: y), to: CGPoint(x: x + 13, y: y), step: 2.3, size: 1.4,
                shade: i < done ? 0.85 : 0.4)
        }
    }
}

/// An hourglass of dots, sand trickling from the top bulb to the bottom, turning over each time.
private enum HourglassProp {
    static func draw(_ ink: inout PropInk, _ t: Double) {
        let c = CGPoint(x: 28, y: 0)
        let cycle = (t * 0.32).truncatingRemainder(dividingBy: 1)
        // The glass: two triangles meeting at the waist.
        ink.line(
            from: CGPoint(x: c.x - 5, y: c.y - 8.5), to: CGPoint(x: c.x + 5, y: c.y - 8.5), step: 2,
            size: 1.2, shade: 0.7)
        ink.line(
            from: CGPoint(x: c.x - 5, y: c.y + 8.5), to: CGPoint(x: c.x + 5, y: c.y + 8.5), step: 2,
            size: 1.2, shade: 0.7)
        ink.line(
            from: CGPoint(x: c.x - 5, y: c.y - 8.5), to: CGPoint(x: c.x, y: c.y), step: 2.2,
            size: 1.1, shade: 0.6)
        ink.line(
            from: CGPoint(x: c.x + 5, y: c.y - 8.5), to: CGPoint(x: c.x, y: c.y), step: 2.2,
            size: 1.1, shade: 0.6)
        ink.line(
            from: CGPoint(x: c.x, y: c.y), to: CGPoint(x: c.x - 5, y: c.y + 8.5), step: 2.2,
            size: 1.1, shade: 0.6)
        ink.line(
            from: CGPoint(x: c.x, y: c.y), to: CGPoint(x: c.x + 5, y: c.y + 8.5), step: 2.2,
            size: 1.1, shade: 0.6)
        // The sand: fewer grains on top as more gather below, and one falling through the waist.
        let top = Int(round(4 * (1 - cycle)))
        let grains: [(Double, Double)] = [(0, -4.2), (-1.4, -5.2), (1.4, -5.2), (0, -6.0)]
        for (i, g) in grains.enumerated() where i < top { ink.dot(c.x + g.0, c.y + g.1, 1.2) }
        let bottom: [(Double, Double)] = [(0, 5.6), (-1.4, 5.6), (1.4, 5.6), (0, 4.4)]
        for (i, g) in bottom.enumerated() where i < 4 - top { ink.dot(c.x + g.0, c.y + g.1, 1.2) }
        let fall = (t * 2.2).truncatingRemainder(dividingBy: 1)
        ink.dot(c.x, c.y - 1 + 4 * fall, 0.9, 0.9)
    }
}

/// Dots appearing in a row beneath the pebble, like words being typed, then starting a new line.
enum TypedProp {
    static func progress(_ t: Double) -> Double { (t * 0.6).truncatingRemainder(dividingBy: 1) }

    fileprivate static func draw(_ ink: inout PropInk, _ t: Double) {
        let p = progress(t)
        let count = 9
        for i in 0..<count where Double(i) / Double(count) < p {
            // Gaps between "words".
            if i == 3 || i == 6 { continue }
            ink.dot(-11 + Double(i) * 2.8, 22, 1.6, 0.9)
        }
        // The caret.
        let caret = -11 + Double(Int(p * Double(count))) * 2.8
        let blink = (t * 2).truncatingRemainder(dividingBy: 1) < 0.6 ? 1.0 : 0.2
        ink.line(
            from: CGPoint(x: caret + 1.4, y: 19.6), to: CGPoint(x: caret + 1.4, y: 24.4), step: 1.6,
            size: 1.2, shade: blink)
    }
}

/// Loose dots drifting in from around the pebble and settling into a neat stack.
private enum TidyProp {
    static func draw(_ ink: inout PropInk, _ t: Double) {
        let cycle = (t * 0.45).truncatingRemainder(dividingBy: 1)
        let homes: [CGPoint] = (0..<9).map { i in
            CGPoint(x: 25 + Double(i % 3) * 3, y: 7 - Double(i / 3) * 3)
        }
        let starts: [CGPoint] = [
            CGPoint(x: 31, y: -12), CGPoint(x: 22, y: -16), CGPoint(x: 37, y: 0),
            CGPoint(x: 22, y: 17), CGPoint(x: 34, y: 15), CGPoint(x: 27, y: -19),
            CGPoint(x: 38, y: -9), CGPoint(x: 26, y: 20), CGPoint(x: 39, y: 9),
        ]
        for i in 0..<homes.count {
            let arrive = propEase((cycle - Double(i) * 0.06) / 0.45)
            let leave = cycle > 0.9 ? propEase((cycle - 0.9) / 0.1) : 0
            let x = starts[i].x + (homes[i].x - starts[i].x) * arrive
            let y = starts[i].y + (homes[i].y - starts[i].y) * arrive
            ink.dot(x, y, 1.8, 1 - leave)
        }
    }
}

/// A question mark of dots above the pebble, bobbing gently.
private enum QuestionProp {
    static func draw(_ ink: inout PropInk, _ t: Double) {
        let bob = 1.2 * sin(t * 2.2)
        let c = CGPoint(x: 21, y: -21 + bob)
        let hook: [CGPoint] = [
            CGPoint(x: -2.6, y: -2.2), CGPoint(x: -1.4, y: -4.0), CGPoint(x: 0.6, y: -4.4),
            CGPoint(x: 2.4, y: -3.4), CGPoint(x: 2.8, y: -1.4), CGPoint(x: 1.6, y: 0.4),
            CGPoint(x: 0.2, y: 1.6), CGPoint(x: 0.2, y: 3.4),
        ]
        for p in hook { ink.dot(c.x + p.x * 1.35, c.y + p.y * 1.35, 1.9) }
        ink.dot(c.x + 0.3, c.y + 8.6, 2.3)
    }
}
