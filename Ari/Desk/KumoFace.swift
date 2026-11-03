import AriKit
import SwiftUI

/// How Kumo feels, for its face: the moods it draws. One the box sends that Ari doesn't know shows
/// as calm.
enum FaceMood: String, CaseIterable {
    case bright, calm, proud, focused, cosy, concerned, drowsy

    init(_ mood: KumoMood?) {
        self = mood.flatMap { FaceMood(rawValue: $0.shown.rawValue) } ?? .calm
    }

    /// The mood in a word, for VoiceOver.
    var spoken: String {
        switch self {
        case .bright: "bright"
        case .calm: "calm"
        case .proud: "proud"
        case .focused: "focused"
        case .cosy: "cosy"
        case .concerned: "a little worried"
        case .drowsy: "drowsy"
        }
    }
}

/// Kumo as a halftone pebble on a faint cushion of dots, whose mood shows in its eyes, how dense
/// and lit its dots are, how it sits and how slowly it breathes. With somewhere to glance, it looks
/// there most of the time and back at you now and then.
struct KumoFace: View {
    let mood: FaceMood
    var size: CGFloat = 136
    /// Where it glances, in its own units (the pebble spans about ±18 by ±16).
    var glance: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: size, height: size * 0.92)
            .overlay {
                TimelineView(.animation(paused: reduceMotion)) { context in
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

    /// How a mood looks: the dots' spacing, size, light and lamp-warmth, how high it sits, how it
    /// breathes, and its tilt in degrees.
    struct Look {
        var spacing: Double
        var fill: Double
        var light: Double
        var warmth: Double
        var lift: Double
        var breathPeriod: Double
        var breathDepth: Double
        var tilt: Double
    }

    static func look(_ mood: FaceMood) -> Look {
        switch mood {
        case .bright:
            Look(
                spacing: 2.1, fill: 0.44, light: 1, warmth: 0, lift: 1.2, breathPeriod: 4.5,
                breathDepth: 0.02, tilt: 0)
        case .calm:
            Look(
                spacing: 2.2, fill: 0.43, light: 0.92, warmth: 0.06, lift: 0.5, breathPeriod: 5.5,
                breathDepth: 0.018, tilt: 0)
        case .proud:
            Look(
                spacing: 2.1, fill: 0.46, light: 1, warmth: 0.12, lift: 2, breathPeriod: 4,
                breathDepth: 0.024, tilt: -3)
        case .focused:
            Look(
                spacing: 1.95, fill: 0.42, light: 0.9, warmth: 0, lift: 0.6, breathPeriod: 5,
                breathDepth: 0.012, tilt: 0)
        case .cosy:
            Look(
                spacing: 2.35, fill: 0.46, light: 0.86, warmth: 0.5, lift: 0, breathPeriod: 6.5,
                breathDepth: 0.026, tilt: 4)
        case .concerned:
            // Slumped low on its cushion and leaning well over, unlike focused, which sits up
            // straight and looks down at its work.
            Look(
                spacing: 2.4, fill: 0.4, light: 0.74, warmth: 0, lift: -1.8, breathPeriod: 3.4,
                breathDepth: 0.014, tilt: -9)
        case .drowsy:
            Look(
                spacing: 2.9, fill: 0.36, light: 0.45, warmth: 0.15, lift: -1, breathPeriod: 8,
                breathDepth: 0.035, tilt: 6)
        }
    }

    private func draw(in canvas: inout GraphicsContext, area: CGSize, t: Double) {
        let look = Self.look(mood)
        let scale = size / 40
        let breath = sin(t * 2 * .pi / look.breathPeriod)
        let gaze = gaze(at: t)

        // Props sit still beside the pebble.
        var props = canvas
        props.translateBy(x: area.width / 2, y: area.height / 2)
        props.scaleBy(x: scale, y: scale)
        drawProps(in: props, t: t)

        // Something to sit on: a faint cushion of dots, which stays put.
        var seat = canvas
        seat.translateBy(x: area.width / 2, y: area.height / 2)
        seat.scaleBy(x: scale, y: scale)
        drawCushion(in: seat)

        canvas.translateBy(
            x: area.width / 2 + gaze.x * 0.25 * scale,
            y: area.height / 2 + (gaze.y * 0.15 - look.lift - 0.6 * breath) * scale)
        canvas.scaleBy(x: scale, y: scale)
        canvas.rotate(by: .degrees(gaze.x * 0.8 + look.tilt))
        canvas.scaleBy(x: 1 - look.breathDepth * 0.4 * breath, y: 1 + look.breathDepth * breath)

        // The halftone: denser and brighter when lively, sparse and dusky when sleepy, the dots
        // swelling and settling in a slow ripple.
        var dots = Path()
        let step = look.spacing
        var row = 0
        for y in stride(from: -16.0, through: 16.0, by: step * 0.87) {
            let shift = row.isMultiple(of: 2) ? 0 : step / 2
            row += 1
            let b = 15.5
            for x in stride(from: -18.0 + shift, through: 18.0, by: step) {
                let a = 17.5 * (1 + 0.04 * y / b)
                guard pow(abs(x / a), 2.3) + pow(abs(y / b), 2.3) <= 1 else { continue }
                let distance = min(1, hypot(x / 17.5, y / 15.5))
                let ripple = 1 + 0.08 * sin(t * 0.9 - x * 0.25 + y * 0.18)
                let r = step * look.fill * (1 - 0.38 * distance * distance) * ripple
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
        let lamp = Color(red: 0.96, green: 0.74, blue: 0.5)
        let fill = Color.ariDusk.mix(with: .ariBone, by: look.light).mix(
            with: lamp, by: 0.35 * look.warmth)
        canvas.fill(dots, with: .color(fill))

        drawEyes(in: canvas, gaze: gaze, t: t)
    }

    private func drawCushion(in canvas: GraphicsContext) {
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
    }

    /// Toward the glance for most of a slow cycle, back at you for the rest. Without one: at you,
    /// swaying a little; down at its work while focused; up at you, anxiously, while concerned.
    private func gaze(at t: Double) -> CGPoint {
        let you: CGPoint =
            switch mood {
            case .focused: CGPoint(x: 0.5 * sin(t * 0.45), y: 2.6)
            case .concerned: CGPoint(x: -0.8 + 0.3 * sin(t * 0.6), y: -0.6)
            default: CGPoint(x: 0.5 * sin(t * 0.45), y: 1.2)
            }
        guard let glance else { return you }
        let phase = t.truncatingRemainder(dividingBy: 9)
        let toward =
            phase < 0.5
            ? Ease.inOut(phase / 0.5)
            : phase < 6.5 ? 1 : phase < 7 ? 1 - Ease.inOut((phase - 6.5) / 0.5) : 0
        return CGPoint(
            x: you.x + (glance.x - you.x) * toward, y: you.y + (glance.y - you.y) * toward)
    }

    private func blink(at t: Double) -> Double {
        let period = mood == .drowsy ? 5.5 : 3.7
        let length = mood == .drowsy ? 0.6 : 0.16
        let phase = t.truncatingRemainder(dividingBy: period)
        return phase < length ? sin(.pi * phase / length) : 0
    }

    private func drawEyes(in canvas: GraphicsContext, gaze: CGPoint, t: Double) {
        let ink = Color.ariBackground
        let closing = 1 - 0.92 * blink(at: t)
        for side in [-1.0, 1.0] {
            let cx = side * 6.4 + gaze.x
            let cy = -1 + gaze.y
            if mood == .proud {
                // Smiling eyes: an upturned arc.
                var arc = Path()
                arc.move(to: CGPoint(x: cx - 2.5, y: cy + 1.1))
                arc.addQuadCurve(
                    to: CGPoint(x: cx + 2.5, y: cy + 1.1), control: CGPoint(x: cx, y: cy - 3.4))
                canvas.stroke(
                    arc, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                continue
            }
            let (width, height): (Double, Double) =
                switch mood {
                case .bright: (4.8, 6.6)
                case .calm: (4.8, 6.2)
                case .focused, .cosy: (5, 6)
                case .concerned: (4.4, 6.4)
                case .drowsy: (5, 5.2)
                case .proud: (0, 0)
                }
            let eye = Path(
                ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            // The lid: what's above it is hidden.
            var lid = Path()
            switch mood {
            case .focused:
                lid.addRect(CGRect(x: -4, y: -1.3, width: 8, height: 8))
            case .cosy:
                lid.addRect(CGRect(x: -4, y: -0.1, width: 8, height: 8))
            case .drowsy:
                lid.addRect(CGRect(x: -4, y: 1.0, width: 8, height: 8))
            case .concerned:
                // Worried: the inner corner raised high, the outer one dropped, so each eye
                // slants down and away from the middle.
                let inner = -side
                lid.move(to: CGPoint(x: 3 * inner, y: -4.6))
                lid.addLine(to: CGPoint(x: -3 * inner, y: 1.4))
                lid.addLine(to: CGPoint(x: -3 * inner, y: 5))
                lid.addLine(to: CGPoint(x: 3 * inner, y: 5))
                lid.closeSubpath()
            default:
                lid.addRect(CGRect(x: -4, y: -5, width: 8, height: 10))
            }
            let shape = eye.intersection(lid)
                .applying(CGAffineTransform(scaleX: 1, y: closing))
                .applying(CGAffineTransform(translationX: cx, y: cy))
            canvas.fill(shape, with: .color(ink))
        }
    }

    /// A twinkle when proud, drifting z's when drowsy.
    private func drawProps(in canvas: GraphicsContext, t: Double) {
        switch mood {
        case .proud:
            let twinkle = 0.55 + 0.45 * sin(t * 2.1)
            let ink = PropInk(canvas: canvas, opacity: twinkle)
            let c = CGPoint(x: 22, y: -18)
            ink.dot(c.x, c.y, 2.2)
            for (dx, dy) in [(0.0, -3.4), (0.0, 3.4), (-3.4, 0.0), (3.4, 0.0)] {
                ink.dot(c.x + dx, c.y + dy, 1.2)
            }
            PropInk(canvas: canvas, opacity: 1 - twinkle * 0.6).dot(28, -10, 1.5)
        case .drowsy:
            for i in 0..<2 {
                let phase = (t / 5 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                let ink = PropInk(canvas: canvas, opacity: sin(phase * .pi) * 0.8)
                let s = 0.7 + 0.5 * phase
                let o = CGPoint(x: 19 + 7 * phase, y: -12 - 12 * phase)
                let z: [(Double, Double)] = [
                    (-2, -2), (0, -2), (2, -2), (0.7, -0.7), (-0.7, 0.7), (-2, 2), (0, 2), (2, 2),
                ]
                for (dx, dy) in z { ink.dot(o.x + dx * s, o.y + dy * s, 1.1 * s + 0.2) }
            }
        default:
            break
        }
    }
}

#if DEBUG
    /// Kumo's moods side by side, for checking they read apart: `ARI_MOODS` opens Ari on it.
    struct KumoMoods: View {
        var body: some View {
            LazyVGrid(columns: [GridItem(), GridItem()], spacing: 46) {
                ForEach(FaceMood.allCases, id: \.self) { mood in
                    VStack(spacing: 24) {
                        KumoFace(mood: mood, size: 92)
                        Text(mood.rawValue).font(.footnote).foregroundStyle(.ariTertiary)
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ariBackground)
        }
    }

    #Preview("Kumo's moods") {
        KumoMoods().preferredColorScheme(.dark)
    }
#endif
