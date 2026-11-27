#if DEBUG
    import AriKit
    import SwiftUI

    // MARK: - The scene

    /// One of your events, in hours since midnight.
    struct SketchEvent: Identifiable {
        var id: String { title }
        let start: Double
        let length: Double
        let title: String

        var time: String { SketchClock.time(start) }
    }

    enum SketchClock {
        static func time(_ hour: Double) -> String {
            let minutes = Int((hour * 60).rounded())
            return String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
        }
    }

    /// Where the moon or sun sits, and the bubble beside it.
    enum CuePlacement {
        /// Over Kumo's left shoulder, the bubble at its right, level with its eyes.
        case shoulders
        /// High in the day's sky, top right, where the light comes from.
        case sky
        /// On the ground beside Kumo, at the end of its cushion.
        case cushion

        var label: String {
            switch self {
            case .shoulders: "A · OVER KUMO'S SHOULDER"
            case .sky: "B · IN THE SKY"
            case .cushion: "C · ON THE CUSHION"
            }
        }
    }

    enum DriftStage { case drifting, word, nextWord }

    enum SleepState: Equatable {
        case asleep
        case dreaming(DriftStage)
        case dreamt
    }

    /// One moment of the Desk: the hour, Kumo's mood and line, what waits, the sky, the day.
    struct M9Scene {
        var hour: Double
        var mood: FaceMood
        var line: String
        var italic = false
        var waiting = 0
        var sky: SkyGlyph.Kind?
        var events: [SketchEvent]
        var tomorrow: SketchEvent?
        var ambient: String?
        var offline: String?
        var sleep: SleepState?
        var caption: String?
        var labelled = true

        static let today: [SketchEvent] = [
            SketchEvent(start: 14, length: 1, title: "Northwind final"),
            SketchEvent(start: 17.5, length: 0.75, title: "Run with Leo"),
            SketchEvent(start: 19.5, length: 1.5, title: "Dinner at Kiln"),
        ]

        static let morning = M9Scene(
            hour: 7 + 40 / 60, mood: .bright,
            line: "Morning. Northwind at 2, and I tidied up overnight.",
            waiting: 2, sky: .moon, events: today)

        static let afternoon = M9Scene(
            hour: 16.5, mood: .proud,
            line: "That's the hard one done, and done well. The rest of today is yours.",
            sky: .sun, events: today)

        static let evening = M9Scene(
            hour: 21.5, mood: .cosy, line: "“Rest is not idleness.”", italic: true, waiting: 1,
            sky: .dusk, events: today,
            tomorrow: SketchEvent(start: 10, length: 1, title: "Coffee with Mira"), labelled: false)

        /// The night before the dream: tomorrow's run still at 08:15.
        static let before: [SketchEvent] = [
            SketchEvent(start: 8.25, length: 0.75, title: "Run with Leo"),
            SketchEvent(start: 14, length: 1, title: "Northwind final"),
        ]

        /// After it: the run moved before the rain.
        static let after: [SketchEvent] = [
            SketchEvent(start: 7.5, length: 0.75, title: "Run with Leo"),
            SketchEvent(start: 14, length: 1, title: "Northwind final"),
        ]

        static let asleep = M9Scene(
            hour: 3 + 50 / 60, mood: .drowsy, line: "Goodnight. I'll dream over today at four.",
            events: before, sleep: .asleep, labelled: false)

        static func dreaming(_ stage: DriftStage) -> M9Scene {
            M9Scene(
                hour: stage == .drifting ? 4.1 : stage == .word ? 4.15 : 4.23, mood: .drowsy,
                line: "Sorting through yesterday.", italic: true, events: before,
                sleep: .dreaming(stage), caption: "Dreaming · tap to watch", labelled: false)
        }

        static let dreamt = M9Scene(
            hour: 4 + 31 / 60, mood: .drowsy, line: "All sorted. It'll keep till morning.",
            sky: .moon, events: after, sleep: .dreamt, labelled: false)

        static let offline = M9Scene(
            hour: 14.5, mood: .bright, line: "Go get them. I'll be right here after.",
            waiting: 2, sky: .sun, events: today, offline: "Offline · updated 14:02",
            labelled: false)
    }

    /// What the Desk opens, for a still of a page.
    enum DeskOpens: Hashable, Identifiable {
        case night(NightShown)
        case plans(detail: Bool)
        case knowYou(question: Bool)

        var id: Self { self }
    }

    enum NightShown: Hashable { case top, lower, dreamLine, manual, doneDetail, replay }

    // MARK: - The Desk

    /// The approved Desk (Kumo a sixth down, its serif line, the day's thread at the foot) with
    /// What I'm up to split into cues that live in the scene: the needs-you bubble, which comes
    /// and goes; the moon, from the dream until you've looked, then the sun; and Kumo itself.
    struct M9Desk: View {
        let scene: M9Scene
        let placement: CuePlacement
        var opens: DeskOpens?

        @State private var shown: DeskOpens?

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: geometry.size.height / 6)
                        kumo
                        words.padding(.top, 34)
                        Spacer(minLength: 16)
                        SketchThread(
                            hour: scene.hour, events: scene.events, tomorrow: scene.tomorrow
                        )
                        .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 28)
                    if case .dreaming(let stage) = scene.sleep {
                        DriftOverlay(stage: stage, scale: 1)
                            .frame(
                                width: geometry.size.width, height: geometry.size.height / 6 + 120
                            )
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background {
                SketchDayLight(
                    hour: scene.hour, center: placement == .sky ? UnitPoint(x: 0.84, y: 0.06) : nil
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .topTrailing) {
                if placement == .sky, let sky = scene.sky {
                    SkyGlyph(kind: sky, side: 66)
                        .padding(.top, 44)
                        .padding(.trailing, 30)
                }
            }
            .overlay(alignment: .top) { topLine.padding(.top, 8) }
            .sheet(item: $shown) { opens in
                Group {
                    switch opens {
                    case .night(let night): NightPage(shown: night)
                    case .plans(let detail): PlansPage(opensDetail: detail)
                    case .knowYou(let question): KnowYouPage(opensQuestion: question)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ariBackground)
            }
            .task {
                guard let opens else { return }
                try? await Task.sleep(for: .milliseconds(400))
                shown = opens
            }
        }

        /// The top of the scene: the variant's label in a still, or the offline marker.
        @ViewBuilder
        private var topLine: some View {
            if let offline = scene.offline {
                OfflineMarker(text: offline)
            } else if let ambient = scene.ambient {
                Text(ambient).font(.footnote).foregroundStyle(.ariTertiary)
            } else if scene.labelled, opens == nil {
                M9VariantLabel(text: placement.label)
            }
        }

        private var asleep: Bool { scene.sleep != nil }

        /// Kumo, the door to getting to know you; beside it the bubble when something waits, and
        /// the moon or sun where this variant puts it.
        private var kumo: some View {
            Group {
                if asleep {
                    SleepingKumo(
                        size: 150,
                        settling: scene.sleep == .dreamt || scene.sleep == .asleep ? 0 : 1,
                        zs: scene.sleep == .asleep)
                } else {
                    KumoFace(
                        mood: scene.mood, size: 150,
                        glance: scene.waiting > 0 ? CGPoint(x: 3.6, y: 0.2) : nil)
                }
            }
            .overlay(alignment: .topTrailing) {
                if scene.waiting > 0 {
                    NeedsYouBubble(count: scene.waiting)
                        .offset(x: 98, y: 30)
                }
            }
            .overlay(alignment: .topLeading) {
                if placement == .shoulders, let sky = scene.sky {
                    SkyGlyph(kind: sky, side: 62)
                        .offset(x: -72, y: -38)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if placement == .cushion, let sky = scene.sky {
                    SkyGlyph(kind: sky, side: 50, grounded: true)
                        .offset(x: -52, y: 0)
                }
            }
        }

        private var words: some View {
            VStack(spacing: 10) {
                Text(scene.line)
                    .font(
                        scene.italic
                            ? .system(.title2, design: .serif).italic()
                            : .system(.title2, design: .serif)
                    )
                    .foregroundStyle(asleep ? Color.ariSecondary : .ariText)
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = scene.caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                }
            }
            .frame(maxWidth: 320)
        }
    }

    /// The needs-you bubble, exactly as today's: it only shows while something waits.
    struct NeedsYouBubble: View {
        let count: Int

        var body: some View {
            Text("\(count) for you")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ariBone)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.ariBone.opacity(0.17)))
                .overlay(Capsule().strokeBorder(Color.ariBone.opacity(0.45), lineWidth: 0.7))
                .fixedSize()
        }
    }

    /// "Offline · updated 14:02": a quiet capsule with a struck-through cloud.
    struct OfflineMarker: View {
        let text: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "icloud.slash")
                    .font(.caption.weight(.semibold))
                Text(text)
            }
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.ariText.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Color.ariLine, lineWidth: 0.7))
        }
    }

    // MARK: - The day's light, for a set hour

    struct SketchDayLight: View {
        let hour: Double
        var center: UnitPoint?

        var body: some View {
            let light = DayLight.light(hour)
            ZStack {
                Color.ariBackground
                RadialGradient(
                    colors: [
                        light.color.opacity(light.strength),
                        light.color.opacity(light.strength * 0.35), .clear,
                    ],
                    center: center ?? light.center, startRadius: 0, endRadius: light.reach)
            }
        }
    }

    // MARK: - The day's thread, for a set hour

    /// The real thread's drawing, from hours rather than calendar items.
    struct SketchThread: View {
        let hour: Double
        let events: [SketchEvent]
        var tomorrow: SketchEvent?

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { canvas, size in draw(in: &canvas, size: size) }
                        .frame(height: 30)
                        .offset(y: 14)
                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize()
                        .position(x: min(max(x(hour, width), 12), width - 12), y: 8)
                    label
                        .font(.footnote)
                        .fixedSize()
                        .position(
                            x: next == nil
                                ? width / 2
                                : min(max(x(next?.start ?? hour, width), 80), width - 80),
                            y: 58)
                }
            }
            .frame(height: 70)
        }

        private var next: SketchEvent? { events.first { $0.start > hour } }

        @ViewBuilder
        private var label: some View {
            if let next {
                Text(
                    "\(Text(next.time).monospacedDigit().foregroundStyle(.ariTertiary))  \(next.title)"
                )
                .foregroundStyle(.ariSecondary)
            } else if let tomorrow {
                Text(
                    "\(Text("Tomorrow \(tomorrow.time)").monospacedDigit().foregroundStyle(.ariTertiary))  \(tomorrow.title)"
                )
                .foregroundStyle(.ariTertiary)
            } else {
                Text("Nothing more today").foregroundStyle(.ariTertiary)
            }
        }

        private var first: Double { min(7, events.map(\.start).min() ?? 7) }

        private func x(_ hour: Double, _ width: CGFloat) -> CGFloat {
            let inset: CGFloat = 6
            let fraction = (min(max(hour, first), 24) - first) / (24 - first)
            return inset + CGFloat(fraction) * (width - 2 * inset)
        }

        private func draw(in canvas: inout GraphicsContext, size: CGSize) {
            let y = size.height / 2
            let now = x(hour, size.width)
            var travelled = Path()
            var ahead = Path()
            var at: CGFloat = 0
            while at <= size.width {
                if at <= now {
                    travelled.addEllipse(in: CGRect(x: at - 1, y: y - 1, width: 2, height: 2))
                    at += 4
                } else {
                    ahead.addEllipse(in: CGRect(x: at - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                    at += 7
                }
            }
            canvas.fill(travelled, with: .color(.ariSecondary.opacity(0.7)))
            canvas.fill(ahead, with: .color(.ariTertiary.opacity(0.55)))
            for event in events {
                let from = x(event.start, size.width)
                let to = max(from + 1, x(event.start + event.length, size.width))
                var knot = Path()
                var dot = from
                while dot <= to {
                    knot.addEllipse(in: CGRect(x: dot - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
                    dot += 4.6
                }
                let past = event.start + event.length < hour
                let shade: Color =
                    event.id == next?.id
                    ? .ariText : past ? .ariTertiary.opacity(0.8) : .ariSecondary
                canvas.fill(knot, with: .color(shade))
            }
            let ring = CGRect(x: now - 5.5, y: y - 5.5, width: 11, height: 11)
            canvas.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
            canvas.stroke(
                Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText), lineWidth: 1.2)
            canvas.fill(Path(ellipseIn: ring.insetBy(dx: 3.6, dy: 3.6)), with: .color(.ariText))
        }
    }

    // MARK: - The moon and the sun

    /// The moon (a halftone crescent with a faint dark side and two stars) or the sun (a halftone
    /// disc with dotted rays), in Kumo's bone dots. Dusk is the sun low and amber, for the evening.
    struct SkyGlyph: View {
        enum Kind { case moon, sun, dusk }
        let kind: Kind
        var side: CGFloat = 46
        /// Sitting on the ground, with a faint cushion of its own.
        var grounded = false

        var body: some View {
            Canvas { canvas, size in
                draw(in: canvas, size: size)
            }
            .frame(width: side * 1.5, height: side * 1.5)
            .frame(width: side, height: side)
            .contentShape(Circle())
            .accessibilityLabel(kind == .moon ? "Last night" : "Today")
        }

        static let lamp = Color(red: 0.96, green: 0.74, blue: 0.5)

        private func draw(in canvas: GraphicsContext, size: CGSize) {
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = side * 0.40
            let step = side / 10
            // A soft glow behind.
            let glow: Color =
                switch kind {
                case .moon: Color(red: 0.72, green: 0.78, blue: 0.95)
                case .sun: Self.lamp
                case .dusk: Color(red: 0.98, green: 0.6, blue: 0.3)
                }
            canvas.fill(
                Path(
                    ellipseIn: CGRect(
                        x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                with: .radialGradient(
                    Gradient(colors: [glow.opacity(kind == .dusk ? 0.16 : 0.2), .clear]),
                    center: c, startRadius: 0, endRadius: r * 1.6))
            switch kind {
            case .moon: moon(canvas, c, r, step)
            case .sun: sun(canvas, c, r, step, light: 1, warmth: 0.35)
            case .dusk: sun(canvas, c, r, step, light: 0.7, warmth: 0.8)
            }
            if grounded {
                var seat = Path()
                for x in stride(from: -r, through: r, by: step * 0.9) {
                    let u = x / r
                    let d = step * 0.18 * (1 - 0.5 * u * u)
                    seat.addEllipse(
                        in: CGRect(
                            x: c.x + x - d, y: c.y + r + step * 0.9 - d, width: 2 * d, height: 2 * d
                        ))
                }
                canvas.fill(seat, with: .color(.ariDusk.opacity(0.4)))
            }
        }

        private func moon(_ canvas: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ step: CGFloat) {
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
                with: .color(
                    Color.ariBone.mix(with: Color(red: 0.8, green: 0.85, blue: 1), by: 0.12)))
            // Two small stars.
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

        private func sun(
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
            let colour = Color.ariDusk.mix(with: .ariBone, by: light).mix(
                with: Self.lamp, by: warmth)
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
#endif
