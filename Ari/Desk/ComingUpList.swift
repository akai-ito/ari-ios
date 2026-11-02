import AriKit
import SwiftUI

/// What's coming up, under day labels: Today, Tomorrow, then "Thu 12". Kumo's own blocks (holds,
/// travel, prep, its plan for your day) are dimmed and marked "Kumo"; travel says when to leave; a
/// trip of several days says how many. Kumo's guesses at your day sit in a dashed outline, and a tap
/// says why, with Right and Not right?. Tapping any other row opens the event. With nothing to show
/// it draws nothing: the Desk hides the section.
struct ComingUpList: View {
    let items: [CalendarItem]
    /// The symbol for an all-day item, such as a plane for a trip's days; a calendar otherwise.
    var symbol: (CalendarItem) -> String? = { _ in nil }
    /// Opens the event, in Apple's own event view.
    let open: (CalendarItem) -> Void
    /// Why Kumo guessed a block, for its guesses at your day (working, building, seeing people,
    /// chilling); `nil` for anything that isn't a guess.
    var guess: (CalendarItem) -> String? = { _ in nil }
    /// You said a guess was right, or what it really was.
    var answerGuess: (CalendarItem, GuessAnswer) async throws -> Void = { _, _ in }
    /// A guess shown open from the start, for previews.
    var unfoldedGuess: CalendarItemID?
    /// A guess shown with its choices from the start, for previews.
    var correctingGuess: CalendarItemID?

    @State private var unfolded: CalendarItemID?
    /// The guess showing what it really was, after Not right?.
    @State private var correcting: CalendarItemID?
    /// The guess you're putting in your own words, from Something else….
    @State private var describing: CalendarItem?
    @State private var sending = DeskSending()

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var dayWidth: CGFloat = 74
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
            .onAppear {
                if unfolded == nil { unfolded = unfoldedGuess ?? correctingGuess }
                if correcting == nil { correcting = correctingGuess }
            }
            .sheet(item: $describing) { item in
                GuessWords(item: item) { words in
                    try await answerGuess(item, GuessAnswer(text: words))
                }
                .presentationDetents([.medium])
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

    @ViewBuilder
    private func row(_ item: CalendarItem, dayLabel: String, showsDay: Bool) -> some View {
        if let why = guess(item) {
            guessRow(item, why: why, dayLabel: dayLabel, showsDay: showsDay)
        } else {
            eventRow(item, dayLabel: dayLabel, showsDay: showsDay)
        }
    }

    /// One of Kumo's guesses at your day: its title in a dashed outline, marked "guess". A tap
    /// unfolds why Kumo thinks so, with Right and Not right?, which offers what it really was.
    private func guessRow(_ item: CalendarItem, why: String, dayLabel: String, showsDay: Bool)
        -> some View
    {
        let isOpen = unfolded == item.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                // A failed answer belongs to the guess it was for.
                sending.clearProblem()
                withAnimation(.smooth(duration: 0.3)) { unfolded = isOpen ? nil : item.id }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if !stacked {
                        Text(showsDay ? dayLabel : "")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.ariSecondary)
                            .frame(width: dayWidth, alignment: .leading)
                            .accessibilityHidden(!showsDay)
                    }
                    Text(item.start.date, format: DeskTime.time)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.ariTertiary)
                        .frame(minWidth: timeWidth, alignment: .leading)
                        .padding(.trailing, 8)
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .background {
                            Capsule()
                                .strokeBorder(
                                    Color.ariTertiary.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                                )
                                .padding(.horizontal, -7)
                                .padding(.vertical, -2.5)
                        }
                        .layoutPriority(1)
                    Text("  ·  guess").font(.footnote).foregroundStyle(.ariTertiary)
                    Spacer(minLength: 0)
                }
                .lineLimit(stacked ? nil : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(LeadName.current)'s guess: \(item.title), \(item.start.date.formatted(DeskTime.time))"
            )
            .accessibilityValue(isOpen ? "Shown" : "")
            .accessibilityHint(isOpen ? "Folds it" : "Shows why, and lets you correct it")
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text(why)
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if sending.isSending {
                        DeskWorkingLine(text: "Telling \(LeadName.current)…")
                    } else if correcting == item.id {
                        choices(for: item)
                    } else {
                        HStack(spacing: 18) {
                            Button("Right") { send(.right, for: item) }
                                .fontWeight(.semibold)
                                .foregroundStyle(.ariBone)
                            Button("Not right?") {
                                withAnimation(.smooth(duration: 0.25)) { correcting = item.id }
                            }
                            .foregroundStyle(.ariSecondary)
                        }
                        .font(.footnote)
                        .buttonStyle(.plain)
                    }
                    if let problem = sending.problem { DeskProblemLine(text: problem) }
                }
                .padding(.leading, stacked ? 0 : dayWidth + timeWidth + 8)
                .transition(.opacity)
            }
        }
    }

    /// What it really was: the usual kinds of time, other than the guess, or your own words.
    private func choices(for item: CalendarItem) -> some View {
        WrappingStack(spacing: 8) {
            ForEach(Self.corrections.filter { $0 != item.guess?.activity }, id: \.rawValue) {
                activity in
                GuessChoice(title: Self.name(activity)) {
                    send(GuessAnswer(activity: activity), for: item)
                }
            }
            GuessChoice(title: "Something else…") { describing = item }
        }
        .transition(.opacity)
    }

    private func send(_ answer: GuessAnswer, for item: CalendarItem) {
        Task {
            let failure = "Couldn't tell \(LeadName.current)"
            if await sending.send(
                item.id.rawValue, failure: failure, { try await answerGuess(item, answer) })
            {
                correcting = nil
            }
        }
    }

    /// The kinds of time Not right? offers.
    static let corrections: [Activity] = [.working, .building, .people, .chilling]

    /// An activity as a choice: "Seeing people" for people.
    static func name(_ activity: Activity) -> String {
        switch activity {
        case .working: "Working"
        case .building: "Building"
        case .training: "Training"
        case .people: "Seeing people"
        case .studying: "Studying"
        case .chilling: "Chilling"
        default: "Something else"
        }
    }

    private func eventRow(_ item: CalendarItem, dayLabel: String, showsDay: Bool) -> some View {
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

/// One of the quick choices after Not right?: small and outlined, in the guess's own row.
private struct GuessChoice: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ariText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().strokeBorder(Color.ariLine, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// What a guess really was, in your own words: a field and Save. It becomes the block's title on
/// Kumo's calendar.
private struct GuessWords: View {
    let item: CalendarItem
    let send: (String) async throws -> Void

    @State private var words = ""
    @State private var sending = DeskSending()
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "\(LeadName.current) guessed \(item.title), \(item.start.date.formatted(DeskTime.time))."
                )
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .fixedSize(horizontal: false, vertical: true)
                TextField("What was it?", text: $words)
                    .font(.ariBody)
                    .foregroundStyle(.ariText)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ariField, in: .rect(cornerRadius: 16, style: .continuous))
                if let problem = sending.problem { DeskProblemLine(text: problem) }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(.ariBackground)
            .navigationTitle("Something else")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.ariText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: submit)
                        .fontWeight(.semibold)
                        .foregroundStyle(.ariText)
                        .disabled(trimmed.isEmpty || sending.isSending)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var trimmed: String {
        String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }

    private func submit() {
        let text = trimmed
        guard !text.isEmpty else { return }
        Task {
            if await sending.send(
                "text", failure: "Couldn't tell \(LeadName.current)", { try await send(text) })
            {
                dismiss()
            }
        }
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
