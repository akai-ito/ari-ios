import AriKit
import SwiftUI

/// Today as a dotted thread at the foot of the Desk: dense where the day has been, sparse ahead, a
/// knot for each of your events, now ringed, and only the next event named. After the last one, it
/// names tomorrow's first.
struct DayThread: View {
    /// Your timed events today.
    let events: [CalendarItem]
    /// Tomorrow's first, named once today's are over.
    var tomorrow: CalendarItem?
    let now: Date

    @Environment(\.calendar) private var calendar

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
                nextLabel
                    .font(.footnote)
                    .fixedSize()
                    .position(x: min(max(x(next.map(start) ?? hour, width), 80), width - 80), y: 58)
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var nextLabel: some View {
        if let next {
            Text(
                "\(Text(next.start.date, format: DeskTime.time).monospacedDigit().foregroundStyle(.ariTertiary))  \(next.title)"
            )
            .foregroundStyle(.ariSecondary)
        } else if let tomorrow {
            Text(
                "\(Text("Tomorrow \(tomorrow.start.date.formatted(DeskTime.time))").monospacedDigit().foregroundStyle(.ariTertiary))  \(tomorrow.title)"
            )
            .foregroundStyle(.ariTertiary)
        } else {
            Text("Nothing more today").foregroundStyle(.ariTertiary)
        }
    }

    /// What VoiceOver says: what's next.
    private var spoken: String {
        if let next {
            return "Your day. Next: \(next.title) at \(next.start.date.formatted(DeskTime.time))"
        }
        if let tomorrow {
            return
                "Your day. Nothing more today; tomorrow \(tomorrow.title) at \(tomorrow.start.date.formatted(DeskTime.time))"
        }
        return "Your day. Nothing more today"
    }

    private var hour: Double { DayLight.hour(of: now, calendar: calendar) }

    private var next: CalendarItem? { events.first { $0.start.date > now } }

    private func start(_ item: CalendarItem) -> Double {
        DayLight.hour(of: item.start.date, calendar: calendar)
    }

    private func end(_ item: CalendarItem) -> Double {
        // An event running past midnight ends at the thread's end.
        guard calendar.isDate(item.end.date, inSameDayAs: item.start.date) else { return 24 }
        return DayLight.hour(of: item.end.date, calendar: calendar)
    }

    /// The thread runs from seven, or the first event if earlier, to midnight.
    private var first: Double { min(7, events.map(start).min() ?? 7) }
    private let last = 24.0

    /// Where an hour falls, kept clear of the edges so the ring never clips.
    private func x(_ hour: Double, _ width: CGFloat) -> CGFloat {
        let inset: CGFloat = 6
        let fraction = (min(max(hour, first), last) - first) / (last - first)
        return inset + CGFloat(fraction) * (width - 2 * inset)
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize) {
        let y = size.height / 2
        let now = x(hour, size.width)
        // Travelled: close, small dots. Ahead: sparser and fainter.
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
        // A knot for each event: a short run of bigger dots across its length.
        let next = self.next?.id
        for event in events {
            let from = x(start(event), size.width)
            let to = max(from + 1, x(end(event), size.width))
            var knot = Path()
            var dot = from
            while dot <= to {
                knot.addEllipse(in: CGRect(x: dot - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
                dot += 4.6
            }
            let past = end(event) < hour
            let shade: Color =
                event.id == next ? .ariText : past ? .ariTertiary.opacity(0.8) : .ariSecondary
            canvas.fill(knot, with: .color(shade))
        }
        // Now: a ringed dot.
        let ring = CGRect(x: now - 5.5, y: y - 5.5, width: 11, height: 11)
        canvas.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
        canvas.stroke(
            Path(ellipseIn: ring.insetBy(dx: 1, dy: 1)), with: .color(.ariText), lineWidth: 1.2)
        canvas.fill(Path(ellipseIn: ring.insetBy(dx: 3.6, dy: 3.6)), with: .color(.ariText))
    }
}

#if DEBUG
    #Preview("The day as a thread") {
        let today = DeskSamples.comingUp.filter {
            !$0.allDay && !DayReading.isKumos($0) && Calendar.current.isDateInToday($0.start.date)
        }
        VStack(spacing: 40) {
            DayThread(events: today, now: .now)
            DayThread(events: [], tomorrow: today.first, now: .now)
        }
        .padding(28)
        .frame(maxHeight: .infinity)
        .background(Color.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
