import AriKit
import SwiftUI

/// The moon or the sun in Kumo's bone dots, as it hangs over Kumo's shoulder and heads its page: a
/// halftone crescent with a faint dark side and two small stars, a halftone disc with dotted rays,
/// or that disc low and amber for the evening. Drawn once; it doesn't move, so it costs nothing
/// while it hangs there.
struct SkyGlyph: View {
    let sky: Sky
    var side: CGFloat = 46

    var body: some View {
        Canvas { canvas, size in
            Self.draw(sky, in: canvas, size: size, side: side)
        }
        .frame(width: side * 1.5, height: side * 1.5)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static let lamp = Color(red: 0.96, green: 0.74, blue: 0.5)

    static func draw(_ sky: Sky, in canvas: GraphicsContext, size: CGSize, side: CGFloat) {
        guard sky != .none else { return }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = side * 0.40
        let step = side / 10
        let glow: Color =
            switch sky {
            case .moon: Color(red: 0.72, green: 0.78, blue: 0.95)
            case .dusk: Color(red: 0.98, green: 0.6, blue: 0.3)
            default: lamp
            }
        canvas.fill(
            Path(
                ellipseIn: CGRect(
                    x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
            with: .radialGradient(
                Gradient(colors: [glow.opacity(sky == .dusk ? 0.18 : 0.22), .clear]),
                center: c, startRadius: 0, endRadius: r * 1.6))
        switch sky {
        case .moon: moon(canvas, c, r, step)
        case .dusk: sun(canvas, c, r, step, light: 0.72, warmth: 0.8)
        default: sun(canvas, c, r, step, light: 1, warmth: 0.35)
        }
    }

    private static func moon(_ canvas: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ step: CGFloat)
    {
        let cut = CGPoint(x: c.x + r * 0.62, y: c.y - r * 0.3)
        let cutR = r * 0.8
        var lit = Path()
        var dark = Path()
        var row = 0
        for y in stride(from: c.y - r, through: c.y + r, by: step * 0.87) {
            let shift = row.isMultiple(of: 2) ? 0 : step / 2
            row += 1
            for x in stride(from: c.x - r + shift, through: c.x + r, by: step) {
                let d = hypot(x - c.x, y - c.y)
                guard d <= r else { continue }
                let fromCut = hypot(x - cut.x, y - cut.y) - cutR
                if fromCut > 0 {
                    let edge = min(1, 0.4 + fromCut / (r * 0.45))
                    let rim = 1 - 0.3 * pow(d / r, 2)
                    let s = step * 0.46 * edge * rim
                    lit.addEllipse(in: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s))
                } else {
                    let s = step * 0.14
                    dark.addEllipse(in: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s))
                }
            }
        }
        canvas.fill(dark, with: .color(.ariBone.opacity(0.18)))
        canvas.fill(
            lit,
            with: .color(Color.ariBone.mix(with: Color(red: 0.8, green: 0.85, blue: 1), by: 0.12)))
        for (dx, dy, s) in [(1.05, -0.95, 0.16), (1.3, -0.35, 0.1)] {
            let p = CGPoint(x: c.x + r * dx, y: c.y + r * dy)
            let size = step * s * 3
            canvas.fill(
                Path(
                    ellipseIn: CGRect(
                        x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                with: .color(.ariBone.opacity(0.85)))
        }
    }

    private static func sun(
        _ canvas: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ step: CGFloat, light: Double,
        warmth: Double
    ) {
        let core = r * 0.74
        var disc = Path()
        var row = 0
        for y in stride(from: c.y - core, through: c.y + core, by: step * 0.87) {
            let shift = row.isMultiple(of: 2) ? 0 : step / 2
            row += 1
            for x in stride(from: c.x - core + shift, through: c.x + core, by: step) {
                let d = hypot(x - c.x, y - c.y)
                guard d <= core else { continue }
                let s = step * 0.47 * (1 - 0.35 * pow(d / core, 2))
                disc.addEllipse(in: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s))
            }
        }
        let colour = Color.ariDusk.mix(with: .ariBone, by: light).mix(with: lamp, by: warmth)
        canvas.fill(disc, with: .color(colour))
        var rays = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + .pi / 8
            for (k, dist) in [r * 0.98, r * 1.16].enumerated() {
                let s = step * (k == 0 ? 0.24 : 0.16)
                let p = CGPoint(x: c.x + cos(a) * dist, y: c.y + sin(a) * dist)
                rays.addEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
            }
        }
        canvas.fill(rays, with: .color(colour.opacity(0.85)))
    }
}

extension Sky {
    /// What VoiceOver says for the glyph's button.
    var spoken: String {
        switch self {
        case .moon: "Last night's dream"
        default: "Today"
        }
    }
}
