import SwiftUI

/// The day's light behind the Desk: a soft glow by the hour, cool in the morning, golden late in
/// the afternoon, lamp-warm in the evening and faint after midnight. It drifts very slowly, and
/// holds still under Reduce Motion.
struct DayLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let light = Self.light(Self.hour(of: context.date))
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let drift = UnitPoint(
                x: light.center.x + 0.03 * sin(t / 11), y: light.center.y + 0.02 * cos(t / 13))
            ZStack {
                Color.ariBackground
                RadialGradient(
                    colors: [
                        light.color.opacity(light.strength),
                        light.color.opacity(light.strength * 0.35), .clear,
                    ],
                    center: drift, startRadius: 0, endRadius: light.reach)
            }
        }
        .accessibilityHidden(true)
    }

    /// The hour on this phone's clock, with minutes as a fraction, such as 16.5 for half past four.
    static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }

    /// The glow for an hour: its colour, how strong it is, where it sits and how far it reaches.
    static func light(_ hour: Double) -> (
        color: Color, strength: Double, center: UnitPoint, reach: CGFloat
    ) {
        switch hour {
        case 5..<11:
            (Color(red: 0.58, green: 0.71, blue: 0.90), 0.24, UnitPoint(x: 0.72, y: 0.05), 600)
        case 11..<15:
            (Color(red: 0.86, green: 0.83, blue: 0.75), 0.10, UnitPoint(x: 0.5, y: 0.1), 520)
        case 15..<19:
            (Color(red: 0.97, green: 0.71, blue: 0.38), 0.19, UnitPoint(x: 0.95, y: 0.22), 600)
        case 19..<24:
            (Color(red: 0.98, green: 0.60, blue: 0.30), 0.15, UnitPoint(x: 0.12, y: 0.62), 560)
        default:
            (Color(red: 0.45, green: 0.50, blue: 0.70), 0.07, UnitPoint(x: 0.5, y: 0.25), 440)
        }
    }
}
