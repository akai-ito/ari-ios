import AriKit
import SwiftUI

/// What's coming up, under day labels: Today, Tomorrow, then "Thu 12". Kumo's own blocks (holds,
/// travel, prep) are dimmed and marked "Kumo"; travel says when to leave; a trip of several days
/// says how many. Tapping a row opens the event. With nothing to show it draws nothing: the Desk
/// hides the section.
struct ComingUpList: View {
    let items: [CalendarItem]
    /// The symbol for an all-day item, such as a plane for a trip's days; a calendar otherwise.
    var symbol: (CalendarItem) -> String? = { _ in nil }
    /// Opens the event, in Apple's own event view.
    let open: (CalendarItem) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var dayWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 48

    var body: some View {
        if !items.isEmpty {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.days(items, now: context.date, calendar: calendar), id: \.day) {
                        day in
                        dayView(day, now: context.date)
                    }
                }
            }
        }
    }

    /// Whether the day's label sits above its rows, for the largest type, or in a column beside.
    private var stacked: Bool { typeSize.isAccessibilitySize }

    @ViewBuilder
    private func dayView(_ day: Day, now: Date) -> some View {
        let label = Self.label(for: day.day, now: now, calendar: calendar)
        if stacked {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.ariSecondary)
                ForEach(day.items) { item in row(item, dayLabel: label, showsDay: false) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                    row(item, dayLabel: label, showsDay: index == 0)
                }
            }
        }
    }

    private func row(_ item: CalendarItem, dayLabel: String, showsDay: Bool) -> some View {
        let quiet = Self.isKumos(item)
        return Button {
            open(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !stacked {
                    Text(showsDay ? dayLabel : "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ariSecondary)
                        .frame(width: dayWidth, alignment: .leading)
                        .accessibilityHidden(!showsDay)
                }
                Group {
                    if item.allDay {
                        Image(systemName: symbol(item) ?? "calendar")
                            .font(.footnote)
                            .foregroundStyle(quiet ? Color.ariTertiary : .ariBone)
                            .accessibilityLabel("All day")
                    } else {
                        Text(item.start.date, format: DeskTime.time)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(quiet ? Color.ariTertiary : .ariText)
                    }
                }
                .frame(minWidth: timeWidth, alignment: .leading)
                .padding(.trailing, 8)
                Text(item.title)
                    .font(.subheadline.weight(quiet ? .regular : .medium))
                    .foregroundStyle(quiet ? Color.ariTertiary : .ariText)
                    .layoutPriority(1)
                if let note = note(item) {
                    Text("  ·  \(note)").font(.footnote).foregroundStyle(.ariTertiary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(stacked ? nil : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the event")
    }

    /// The note after the title: "Kumo" for its own blocks, when to leave, how many days, or where.
    private func note(_ item: CalendarItem) -> Text? {
        var parts: [Text] = []
        if Self.isKumos(item) { parts.append(Text("Kumo")) }
        if let leave = item.leaveAt {
            parts.append(Text("leave \(leave.date, format: DeskTime.time)"))
        }
        let days = Self.days(of: item)
        if item.allDay, days > 1 { parts.append(Text("\(days) days")) }
        if !Self.isKumos(item), item.leaveAt == nil, let location = item.location {
            parts.append(Text(location))
        }
        guard var joined = parts.first else { return nil }
        for part in parts.dropFirst() { joined = Text("\(joined) · \(part)") }
        return joined
    }

    // MARK: Reading the calendar

    /// One day's items, all-day ones first, then by time.
    struct Day {
        let day: Date
        let items: [CalendarItem]
    }

    /// Kumo's own blocks, and times it's holding: dimmed, as working notes rather than plans.
    static func isKumos(_ item: CalendarItem) -> Bool {
        item.calendar.kumo || item.status == .hold
    }

    /// The items under the days they fall on. Something that began before today, such as a trip
    /// you're on, sits under today.
    static func days(_ items: [CalendarItem], now: Date, calendar: Calendar) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: items) { max(day(of: $0, calendar: calendar), today) }
        return grouped.keys.sorted().map { day in
            let items = grouped[day, default: []].sorted { a, b in
                if a.allDay != b.allDay { return a.allDay }
                return a.start.date < b.start.date
            }
            return Day(day: day, items: items)
        }
    }

    /// The day an item falls on. An all-day item's start is midnight, but whose midnight depends on
    /// how it was written down (UTC or the box's zone), so it's read from midday instead, which
    /// lands on the same date either way.
    static func day(of item: CalendarItem, calendar: Calendar) -> Date {
        let start = item.allDay ? item.start.date.addingTimeInterval(12 * 3600) : item.start.date
        return calendar.startOfDay(for: start)
    }

    /// How many days an all-day item covers; its end is the morning after its last day.
    static func days(of item: CalendarItem) -> Int {
        max(1, Int((item.end.date.timeIntervalSince(item.start.date) / 86_400).rounded()))
    }

    /// "Today", "Tomorrow", or the weekday and date, such as "Thu 12".
    static func label(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(day, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        return day.formatted(DeskTime.weekdayDay)
    }
}

#if DEBUG
    #Preview("Coming up") {
        VStack(alignment: .leading, spacing: 10) {
            DeskSectionLabel("Coming up")
            ComingUpList(
                items: DeskSamples.comingUp,
                symbol: { $0.motion == "florence" ? "airplane" : nil },
                open: { _ in })
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ariBackground)
        .preferredColorScheme(.dark)
    }
#endif
