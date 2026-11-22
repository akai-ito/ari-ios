import AriKit
import SwiftUI

/// The art for each section of In motion, printed in Ari's bone dots the way Kumo's face and the
/// Library's shelf glyphs are: a picture of tone, drawn as dots on a hex grid, each dot as large
/// as the picture is bright there. Steps for Career, a kettlebell for Body, a banded sun over
/// hills for Trips, stacked blocks for Projects, an open book for Learning, and an egg for Other,
/// the things that haven't hatched into a shape yet.
extension MotionSection {
    /// How bright the art is at a point of its unit square, from 0 to 1.
    func tone(_ x: Double, _ y: Double) -> Double {
        switch self {
        case .career: Self.steps(x, y)
        case .body: Self.kettlebell(x, y)
        case .trips: Self.sunset(x, y)
        case .projects: Self.blocks(x, y)
        case .learning: Self.book(x, y)
        case .other: Self.egg(x, y)
        }
    }

    private static func steps(_ x: Double, _ y: Double) -> Double {
        var ink = Ink()
        let bottom = 0.84
        for (x0, x1, top) in [(0.12, 0.36, 0.62), (0.38, 0.62, 0.45), (0.64, 0.88, 0.28)] {
            let d = SDF.box(
                x, y, cx: (x0 + x1) / 2, cy: (top + bottom) / 2, hw: (x1 - x0) / 2,
                hh: (bottom - top) / 2, r: 0.015)
            let u = (y - top) / (bottom - top)
            ink.lay(SDF.cover(d), u < 0.1 ? 1 : 0.8 - 0.45 * u)
        }
        ink.lay(SDF.cover(SDF.segment(x, y, 0.70, 0.28, 0.70, 0.05) - 0.014), 0.9)
        ink.lay(SDF.cover(SDF.polygon(x, y, [(0.71, 0.05), (0.89, 0.105), (0.71, 0.16)])), 1)
        return ink.value
    }

    private static func kettlebell(_ x: Double, _ y: Double) -> Double {
        var ink = Ink()
        if y < 0.54 {
            let d = abs(SDF.length(x - 0.5, y - 0.37) - 0.165) - 0.046
            ink.lay(SDF.cover(d), clamp(0.95 - 0.7 * (x - 0.32)))
        }
        let r = 0.28
        let cx = 0.5
        let cy = 0.62
        let d = max(SDF.circle(x, y, cx, cy, r), y - 0.87)
        ink.lay(SDF.cover(d), 0.16 + 0.84 * lit((x - cx) / r, (y - cy) / r))
        return ink.value
    }

    private static func sunset(_ x: Double, _ y: Double) -> Double {
        let disc = SDF.circle(x, y, 0.5, 0.5, 0.47)
        guard disc < 0.02 else { return 0 }
        var ink = Ink()
        ink.lay(1, 0.04 + 0.1 * (1 - y))
        // The sun, banded below its middle like an old print: the bands widen as it sets.
        let band = y > 0.44 && ((y - 0.44) / 0.055).truncatingRemainder(dividingBy: 1) > 0.66
        let sun = SDF.circle(x, y, 0.6, 0.44, 0.2)
        ink.lay(band ? 0 : SDF.cover(sun), 1 - 0.3 * max(0, y - 0.3))
        let far = y - (0.63 + 0.05 * sin(x * 8 + 0.6))
        ink.lay(SDF.cover(-far, 0.01), 0.36)
        let near = y - (0.72 + 0.08 * cos((x - 0.26) * 5))
        ink.lay(SDF.cover(-near, 0.01), 0.6 + 0.3 * (y - 0.7))
        return ink.value * SDF.cover(disc)
    }

    private static func blocks(_ x: Double, _ y: Double) -> Double {
        var ink = Ink()
        for (tx, ty, s) in [(0.40, 0.42, 0.24), (0.40, 0.225, 0.13), (0.70, 0.595, 0.15)] {
            let w = 0.866 * s
            let top = [(tx, ty - s / 2), (tx + w, ty), (tx, ty + s / 2), (tx - w, ty)]
            let left = [(tx - w, ty), (tx, ty + s / 2), (tx, ty + 1.5 * s), (tx - w, ty + s)]
            let right = [(tx, ty + s / 2), (tx + w, ty), (tx + w, ty + s), (tx, ty + 1.5 * s)]
            ink.lay(SDF.cover(SDF.polygon(x, y, left)), 0.64)
            ink.lay(SDF.cover(SDF.polygon(x, y, right)), 0.34)
            ink.lay(SDF.cover(SDF.polygon(x, y, top)), 1)
        }
        return ink.value
    }

    private static func book(_ x: Double, _ y: Double) -> Double {
        var ink = Ink()
        let cover = [
            (0.05, 0.34), (0.5, 0.43), (0.95, 0.34), (0.95, 0.79), (0.5, 0.87), (0.05, 0.79),
        ]
        ink.lay(SDF.cover(SDF.polygon(x, y, cover)), 0.28)
        let pages = [
            [(0.08, 0.27), (0.485, 0.36), (0.485, 0.81), (0.08, 0.72)],
            [(0.515, 0.36), (0.92, 0.27), (0.92, 0.72), (0.515, 0.81)],
        ]
        for (index, page) in pages.enumerated() {
            let fromSpine = abs(x - 0.5) / 0.42
            var shade = (index == 0 ? 0.8 : 0.97) * (0.6 + 0.4 * min(1, fromSpine * 2.4))
            // Lines of type, darker rows across the page.
            let top = 0.27 + 0.09 * (1 - fromSpine)
            let row = (y - top - 0.08) / 0.065
            if row > 0, row < 6, fromSpine > 0.18, fromSpine < 0.84,
                row.truncatingRemainder(dividingBy: 1) < 0.4
            {
                shade *= 0.42
            }
            ink.lay(SDF.cover(SDF.polygon(x, y, page)), shade)
        }
        return ink.value
    }

    private static func egg(_ x: Double, _ y: Double) -> Double {
        var ink = Ink()
        let shadow = SDF.length((x - 0.5) / 0.24, (y - 0.875) / 0.035) - 1
        ink.lay(SDF.cover(shadow * 0.03), 0.22)
        let cy = 0.52
        let ry = 0.33
        let rx = 0.25 * (1 + 0.16 * (y - cy) / ry)
        let nx = (x - 0.5) / rx
        let ny = (y - cy) / ry
        let q = SDF.length(nx, ny)
        ink.lay(SDF.cover((q - 1) * rx), 0.14 + 0.86 * lit(nx, ny))
        return ink.value
    }

    /// Light on a sphere's point from the upper left.
    private static func lit(_ nx: Double, _ ny: Double) -> Double {
        let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
        return max(0, -0.48 * nx - 0.56 * ny + 0.67 * nz)
    }
}

/// Paint laid on in order, each coat covering what's under it as much as it covers the point.
struct Ink {
    var value = 0.0

    mutating func lay(_ coverage: Double, _ shade: Double) {
        guard coverage > 0 else { return }
        value = value * (1 - coverage) + shade * coverage
    }
}

/// Signed distances in the art's unit square: below zero inside a shape.
enum SDF {
    static func length(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }

    static func circle(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ r: Double)
        -> Double
    {
        length(x - cx, y - cy) - r
    }

    static func box(
        _ x: Double, _ y: Double, cx: Double, cy: Double, hw: Double, hh: Double, r: Double
    ) -> Double {
        let qx = abs(x - cx) - hw + r
        let qy = abs(y - cy) - hh + r
        return length(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    }

    static func segment(
        _ x: Double, _ y: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double
    ) -> Double {
        let px = x - ax
        let py = y - ay
        let ex = bx - ax
        let ey = by - ay
        let h = clamp((px * ex + py * ey) / (ex * ex + ey * ey))
        return length(px - ex * h, py - ey * h)
    }

    static func polygon(_ x: Double, _ y: Double, _ v: [(Double, Double)]) -> Double {
        var d = (x - v[0].0) * (x - v[0].0) + (y - v[0].1) * (y - v[0].1)
        var s = 1.0
        var j = v.count - 1
        for i in v.indices {
            let ex = v[j].0 - v[i].0
            let ey = v[j].1 - v[i].1
            let wx = x - v[i].0
            let wy = y - v[i].1
            let h = clamp((wx * ex + wy * ey) / (ex * ex + ey * ey))
            let bx = wx - ex * h
            let by = wy - ey * h
            d = min(d, bx * bx + by * by)
            let c1 = y >= v[i].1
            let c2 = y < v[j].1
            let c3 = ex * wy > ey * wx
            if (c1 && c2 && c3) || (!c1 && !c2 && !c3) { s = -s }
            j = i
        }
        return s * d.squareRoot()
    }

    /// How much of a point a shape covers, with a soft edge.
    static func cover(_ d: Double, _ soft: Double = 0.014) -> Double {
        clamp(0.5 - d / soft)
    }
}

/// Prints a picture of tone as dots on a hex grid.
enum Halftone {
    /// `fixed`: every dot the same size, as a share of the step, wherever the tone is above zero.
    static func print(
        in context: GraphicsContext, size: CGSize, across: Double, color: Color,
        fixed: Double? = nil, tone: (Double, Double) -> Double
    ) {
        let step = size.width / across
        let rowStep = step * 0.866
        var dots = Path()
        var row = 0
        var y = rowStep / 2
        while y < size.height {
            var x = step / 2 + (row.isMultiple(of: 2) ? 0 : step / 2)
            while x < size.width {
                let v = tone(x / size.height, y / size.height)
                if v > 0.03 {
                    let r = fixed.map { step * $0 } ?? step * 0.5 * min(v, 1).squareRoot() * 0.97
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                }
                x += step
            }
            y += rowStep
            row += 1
        }
        context.fill(dots, with: .color(color))
    }
}

/// A section's art on a faint disc of dots, as the Library's shelf glyphs sit.
struct HalftoneArt: View {
    let art: MotionSection
    var side: CGFloat = 46
    /// Dots across: fewer reads bolder, more reads finer.
    var across: Double = 25
    /// For something quiet or ended: dusk instead of bone.
    var faded = false
    var ground = true

    var body: some View {
        Canvas { context, size in
            if ground {
                Halftone.print(
                    in: context, size: size, across: across / 1.7,
                    color: Color.ariBone.opacity(faded ? 0.1 : 0.18), fixed: 0.34
                ) { x, y in
                    SDF.circle(x, y, 0.5, 0.5, 0.5) < 0 && art.tone(x, y) < 0.05 ? 1 : 0
                }
            }
            Halftone.print(
                in: context, size: size, across: across,
                color: faded ? Color.ariDusk : Color.ariBone
            ) { art.tone($0, $1) }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A symbol printed as halftone, lit from the upper left, on the same faint disc: for something
/// inside a section that wants its own picture, such as a run within Body.
struct SymbolHalftone: View {
    let symbol: String
    var side: CGFloat = 64
    var across: Double = 28

    var body: some View {
        Canvas { context, size in
            Halftone.print(
                in: context, size: size, across: across / 1.7, color: Color.ariBone.opacity(0.18),
                fixed: 0.34
            ) { x, y in SDF.circle(x, y, 0.5, 0.5, 0.5) < 0 ? 1 : 0 }
            var inked = context
            inked.clipToLayer { layer in
                layer.draw(
                    Text(Image(systemName: symbol)).font(
                        .system(size: size.width * 0.62, weight: .black)),
                    at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
            inked.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.ariBackground))
            Halftone.print(in: inked, size: size, across: across, color: .ariBone) { x, y in
                0.4 + 0.6 * clamp(1.15 - 0.75 * x - 0.55 * y)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// An area filled with an even grid of small dots: something planned, not yet done. Done things
/// are solid; plans are printed in dots.
struct DotFill: View {
    var step: CGFloat = 3.4
    var size: CGFloat = 0.3
    var color: Color = .ariBone

    var body: some View {
        Canvas { context, canvas in
            var dots = Path()
            var y = step / 2
            var row = 0
            while y < canvas.height + step {
                var x = step / 2 + (row.isMultiple(of: 2) ? 0 : step / 2)
                while x < canvas.width + step {
                    let r = step * size
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    x += step
                }
                y += step * 0.866
                row += 1
            }
            context.fill(dots, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}
