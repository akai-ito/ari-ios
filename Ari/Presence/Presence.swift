import AriKit
import SwiftUI

/// What the character is doing, from the turn's status kind and the connection.
enum Pose: Equatable {
    case resting, thinking, searching, writing, adjusting, waiting, stopping
    /// Ari asked you something and waits for your answer.
    case asking
    /// The connection is down: Ari can't hear the server, so the character doesn't pretend to work.
    case offline

    init(kind: StatusKind) {
        switch kind {
        case .working: self = .searching
        case .writing: self = .writing
        case .adjusting: self = .adjusting
        case .waiting: self = .waiting
        case .stopping: self = .stopping
        default: self = .thinking
        }
    }

    /// How awake it looks: lit and lifted while working, half-dimmed when the connection is down,
    /// dusky at rest.
    var level: Double {
        switch self {
        case .resting: 0
        case .offline: 0.45
        default: 1
        }
    }
}

/// The poses the character has been in, and when, so each change can blend into the next.
struct PoseHistory: Equatable {
    private(set) var changes: [(at: Date, pose: Pose)]

    init(_ pose: Pose = .resting, at date: Date = .now) {
        changes = [(date, pose)]
    }

    var current: Pose { changes.last?.pose ?? .resting }

    mutating func set(_ pose: Pose, at date: Date = .now) {
        guard pose != current else { return }
        changes.append((date, pose))
        if changes.count > 8 { changes.removeFirst(changes.count - 8) }
    }

    static func == (lhs: PoseHistory, rhs: PoseHistory) -> Bool {
        lhs.changes.map(\.at) == rhs.changes.map(\.at)
            && lhs.changes.map(\.pose) == rhs.changes.map(\.pose)
    }
}

/// Ari's presence: a pebble of bone-coloured dots with two eyes. It looks down toward the
/// conversation, up while thinking, aside while searching, along the lines while writing, at your
/// message when it takes it in, and lowers its eyes when you stop it. At rest it dims and its eyes
/// fade: a quiet dotted stone. Under Reduce Motion it holds still in each pose.
struct PresenceView: View {
    let history: PoseHistory
    var size: CGFloat = 40

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { canvas, area in
                draw(in: &canvas, area: area, at: context.date)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, area: CGSize, at now: Date) {
        let changes = history.changes
        let origin = changes.first?.at ?? now
        let t = now.timeIntervalSince(origin)
        let starts = changes.map { $0.at.timeIntervalSince(origin) }
        let weights = reduceMotion ? still(starts.count) : segmentWeights(starts, at: t, fade: 0.45)
        let slow = reduceMotion ? still(starts.count) : segmentWeights(starts, at: t, fade: 0.9)
        var gaze = CGPoint.zero
        var awake = 0.0
        var glow = 0.0
        var lids = 0.0
        for (index, change) in changes.enumerated() {
            glow += change.pose.level * slow[index]
            guard weights[index] > 0 else { continue }
            let since = t - starts[index]
            let look = Self.gaze(
                change.pose, since: reduceMotion ? 0 : since, t: reduceMotion ? 0 : t)
            gaze.x += look.x * weights[index]
            gaze.y += look.y * weights[index]
            awake += change.pose.level * weights[index]
            lids += Self.openness(change.pose, since: reduceMotion ? 1 : since) * weights[index]
        }

        let scale = size / 40
        canvas.translateBy(
            x: area.width / 2 + gaze.x * 0.2 * scale,
            y: area.height / 2 + (gaze.y * 0.15 - awake * 0.8) * scale)
        canvas.scaleBy(x: scale, y: scale)
        canvas.rotate(by: .degrees(gaze.x * 0.8))
        let fill = Color.ariDusk.mix(with: .ariBone, by: glow)
        canvas.fill(Self.halftone, with: .color(fill))

        let open = lids * (1 - 0.92 * (reduceMotion ? 0 : blink(at: t, starts: starts)))
        let height = (5.6 + 0.5 * awake) * open
        let shown = eyesShown(at: t, starts: starts)
        for side in [-1.0, 1.0] {
            let eye = CGRect(
                x: side * 6.4 + gaze.x - 2.3, y: -1 + gaze.y - height / 2, width: 4.6,
                height: height)
            canvas.fill(Path(ellipseIn: eye), with: .color(Color.ariBackground.opacity(shown)))
        }
    }

    /// Weights with no blending: all on the latest pose.
    private func still(_ count: Int) -> [Double] {
        (0..<count).map { $0 == count - 1 ? 1 : 0 }
    }

    /// The eyes come in as Ari wakes and, after the slow blink that settles it, fade away.
    private func eyesShown(at t: Double, starts: [Double]) -> Double {
        let changes = history.changes
        guard let index = starts.lastIndex(where: { $0 <= t }) else { return 0 }
        if changes[index].pose != .resting {
            var start = index
            while start > 0, changes[start - 1].pose != .resting { start -= 1 }
            if start == 0 || reduceMotion { return 1 }
            return Ease.out((t - starts[start]) / 0.3)
        }
        guard index > 0, !reduceMotion else { return 0 }
        return 1 - Ease.inOut((t - (starts[index] + 1.3)) / 1.4)
    }

    /// A quick blink on waking, one every few seconds while awake, and a slow one on settling.
    private func blink(at t: Double, starts: [Double]) -> Double {
        let changes = history.changes
        var blinks: [(at: Double, length: Double)] = []
        for (index, change) in changes.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : .infinity
            let previous = index > 0 ? changes[index - 1].pose : nil
            if change.pose == .resting {
                if previous != nil { blinks.append((starts[index] + 0.4, 0.34)) }
                continue
            }
            if previous == .resting { blinks.append((starts[index] + 0.07, 0.16)) }
            if change.pose == .stopping || change.pose == .offline { continue }
            var at = starts[index] + 2.5
            var cycle = 0.0
            while at < min(end, t + 1) {
                blinks.append((at, 0.16))
                cycle += 1
                at += 2.9 + 0.5 * sin(cycle * 1.7)
            }
        }
        for blink in blinks where t >= blink.at && t < blink.at + blink.length {
            return sin(.pi * (t - blink.at) / blink.length)
        }
        return 0
    }

    /// Where the eyes point, in points from centre.
    static func gaze(_ pose: Pose, since: Double, t: Double) -> CGPoint {
        switch pose {
        case .resting: CGPoint(x: 0.5 * sin(t * 0.6), y: 2.2)
        case .thinking: CGPoint(x: 1.4 + 1.2 * sin(since * 1.1), y: -3.0 + 0.3 * sin(since * 0.8))
        case .searching: CGPoint(x: 3.6 * smoothSquare(since / 1.3 + 0.25), y: 0.6)
        case .writing: CGPoint(x: 1.6 * sin(since * 2 * .pi / 1.9), y: 2.8)
        case .adjusting: CGPoint(x: 3.2, y: 2.9 + 0.3 * sin(since * 2))
        case .waiting: CGPoint(x: -1.8 + 0.6 * sin(t * 0.5), y: -2.0)
        case .stopping: CGPoint(x: 0, y: 3.0)
        // Down toward you and the composer, with a slow, patient sway.
        case .asking: CGPoint(x: 0.9 * sin(t * 0.55), y: 3.6 + 0.25 * sin(t * 0.9))
        case .offline: CGPoint(x: 0, y: 1.6)
        }
    }

    /// How open the eyes are, 1 being wide awake.
    static func openness(_ pose: Pose, since: Double) -> Double {
        switch pose {
        case .adjusting: 1.12
        case .waiting: 0.62
        // Open and attentive: it's your turn.
        case .asking: 1.08
        case .offline: 0.5
        case .stopping:
            since < 0.1
                ? 1 - 8.5 * since
                : since < 0.3 ? 0.15 : 0.15 + 0.45 * Ease.out((since - 0.3) / 0.25)
        default: 1
        }
    }

    /// Dots on a staggered grid inside the pebble, shrinking toward its edge as a printed halftone
    /// does, so it reads as round without a gradient.
    static let halftone: Path = {
        let outline = PresenceView.pebble(width: 35, height: 31)
        var dots = Path()
        let spacing = 2.5
        for (row, y) in stride(from: -16.0, through: 16.0, by: spacing * 0.87).enumerated() {
            let shift = row.isMultiple(of: 2) ? 0 : spacing / 2
            for x in stride(from: -18.0 + shift, through: 18.0, by: spacing)
            where outline.contains(CGPoint(x: x, y: y)) {
                let distance = min(1, hypot(x / 17.5, y / 15.5))
                let size = 2.0 - 0.75 * distance * distance
                dots.addEllipse(
                    in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
            }
        }
        return dots
    }()

    /// A superellipse, a little wider at the bottom so it sits rather than floats.
    static func pebble(width: Double, height: Double, roundness: Double = 2.3) -> Path {
        var path = Path()
        let a = width / 2
        let b = height / 2
        for step in 0...120 {
            let angle = Double(step) / 120 * 2 * .pi
            let c = cos(angle)
            let s = sin(angle)
            let y = b * copysign(pow(abs(s), 2 / roundness), s)
            let x = a * copysign(pow(abs(c), 2 / roundness), c) * (1 + 0.04 * y / b)
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Poses") {
    let poses: [Pose] = [
        .resting, .thinking, .searching, .writing, .adjusting, .waiting, .stopping, .offline,
    ]
    let start = Date.now.addingTimeInterval(-10)
    return LazyVGrid(columns: Array(repeating: GridItem(), count: 4), spacing: 24) {
        ForEach(poses.indices, id: \.self) { index in
            var history = PoseHistory(.thinking, at: start)
            let _ = history.set(poses[index], at: start.addingTimeInterval(1))
            VStack {
                PresenceView(history: history)
                Text(String(describing: poses[index])).font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }
    .padding()
    .background(.ariBackground)
}
