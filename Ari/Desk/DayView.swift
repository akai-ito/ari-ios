import AriKit
import SwiftUI

/// Your day in detail, opened from the thread: your events as a calm list, with Kumo's planned and
/// guessed blocks and its check-ins woven in faintly, then tomorrow. Only mine hides Kumo's. Your
/// events open in Apple's own view; each of Kumo's unfolds in place to answer, move or cancel.
struct DayView: View {
    let session: Session
    /// A guess shown open, or with its choices, from the start, for stills.
    var shownGuess: GuessShown?

    enum GuessShown { case open, correct }

    @AppStorage("dayViewOnlyMine") private var onlyMine = false
    @State private var unfolded: String?
    /// The guess showing what it really was, after Not right?.
    @State private var correcting: String?
    /// The guess you're putting in your own words, from Something else….
    @State private var describing: String?
    @State private var words = ""
    @State private var sending = DeskSending()
    @State private var opened: CalendarItem?
    @State private var moving: CalendarItem?
    @State private var editing: WakeUp?
    @State private var removing: CalendarItem?
    @State private var cancelling: WakeUp?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 48

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Picker("Show", selection: $onlyMine) {
                            Text("Everything").tag(false)
                            Text("Only mine").tag(true)
                        }
                        .pickerStyle(.segmented)
                        ForEach(days(now: context.date), id: \.day) { group in
                            daySection(group, now: context.date)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: Rhythm.column, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            .background(.ariBackground)
            .navigationTitle("Your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.ariText)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: unfolded)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: onlyMine)
        }
        .sheet(item: $opened) { CalendarEventView(item: $0) }
        .sheet(item: $moving) { BlockMoveSheet(item: $0, session: session) }
        .sheet(item: $editing) { PlanEditor(plan: $0, session: session) }
        .confirmationDialog(
            "Remove “\(removing?.title ?? "")”?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible, presenting: removing
        ) { item in
            Button("Remove it", role: .destructive) {
                act(item.id.rawValue) { try await session.remove(item.id) }
            }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text(
                "It comes off \(LeadName.current)'s calendar, and \(LeadName.current) sees you took it off. You can undo it from Done."
            )
        }
        .confirmationDialog(
            "Cancel “\(cancelling?.what ?? "")”?",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible, presenting: cancelling
        ) { plan in
            Button("Cancel the check-in", role: .destructive) {
                act(plan.id.rawValue) { try await session.cancel(plan.id) }
            }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("\(LeadName.current) won't set it again unless you ask.")
        }
        .onAppear { showGuess() }
    }

    /// Today, then tomorrow.
    private func days(now: Date) -> [DayGroup] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return [now, tomorrow].map { day in
            let group = DayReading.group(on: day, desk: session.desk, now: now, calendar: calendar)
            guard onlyMine else { return group }
            return DayGroup(day: group.day, entries: group.entries.filter { !$0.isKumos })
        }
    }

    private func daySection(_ group: DayGroup, now: Date) -> some View {
        let isToday = calendar.isDate(group.day, inSameDayAs: now)
        return VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel(
                isToday ? "Today" : "Tomorrow",
                trailing: group.day.formatted(DeskTime.weekdayDayMonth))
            if group.entries.isEmpty {
                Text(onlyMine ? "Nothing on your calendar." : "Nothing planned.")
                    .font(.subheadline)
                    .foregroundStyle(.ariTertiary)
            }
            ForEach(group.entries) { entry in
                row(entry, past: isToday && end(of: entry) < now)
            }
        }
    }

    private func end(of entry: DayEntry) -> Date {
        entry.item.map { $0.end.date } ?? entry.start
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: DayEntry, past: Bool) -> some View {
        let isOpen = unfolded == entry.id
        VStack(alignment: .leading, spacing: 8) {
            Button {
                tap(entry)
            } label: {
                line(entry).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(hint(entry, isOpen: isOpen))
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    unfolding(entry)
                    if let problem = sending.problem { DeskProblemLine(text: problem) }
                }
                .padding(.leading, timeWidth + 10)
                .transition(.opacity)
            }
        }
        .opacity(past ? 0.45 : 1)
    }

    private func line(_ entry: DayEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Group {
                if entry.isAllDay {
                    Image(systemName: "calendar")
                        .font(.footnote)
                        .foregroundStyle(entry.isKumos ? Color.ariTertiary : .ariBone)
                        .accessibilityLabel("All day")
                } else {
                    Text(entry.start, format: DeskTime.time)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(entry.isKumos ? Color.ariTertiary : .ariText)
                }
            }
            .frame(minWidth: timeWidth, alignment: .leading)
            .padding(.trailing, 10)
            switch entry {
            case .event(let item):
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ariText)
                    .layoutPriority(1)
                if let note = note(item) { tag(note) }
            case .block(let item):
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.ariTertiary)
                    .layoutPriority(1)
                tag("planned")
            case .guess(let item):
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
                    .padding(.leading, 7)
                    .layoutPriority(1)
                tag("guess")
            case .checkIn(let plan):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "bell")
                        .font(.caption2)
                        .foregroundStyle(.ariDusk)
                        .accessibilityLabel("Check-in:")
                    Text(plan.what)
                        .font(.subheadline)
                        .foregroundStyle(.ariTertiary)
                }
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func tag(_ text: String) -> some View {
        Text("  ·  \(text)").font(.footnote).foregroundStyle(.ariTertiary).lineLimit(1)
    }

    /// Where it is, or when to leave for it.
    private func note(_ item: CalendarItem) -> String? {
        if let leave = item.leaveAt { return "leave \(leave.date.formatted(DeskTime.time))" }
        return item.location
    }

    private func hint(_ entry: DayEntry, isOpen: Bool) -> String {
        if case .event = entry { return "Opens the event" }
        return isOpen ? "Folds it" : "Shows more, to change it"
    }

    private func tap(_ entry: DayEntry) {
        if case .event(let item) = entry {
            opened = item
            return
        }
        sending.clearProblem()
        correcting = nil
        describing = nil
        unfolded = unfolded == entry.id ? nil : entry.id
    }

    // MARK: Unfolded

    @ViewBuilder
    private func unfolding(_ entry: DayEntry) -> some View {
        switch entry {
        case .event:
            EmptyView()
        case .guess(let item):
            if let why = item.guess?.why { quiet(why) }
            if sending.isSending {
                DeskWorkingLine(text: "Telling \(LeadName.current)…")
            } else if correcting == entry.id {
                choices(for: item, id: entry.id)
            } else {
                actions {
                    Button("Right") { answer(.right, for: item, id: entry.id) }
                        .fontWeight(.semibold)
                        .foregroundStyle(.ariBone)
                    Button("Not right?") { correcting = entry.id }
                        .foregroundStyle(.ariSecondary)
                }
            }
        case .block(let item):
            quiet(blockWords(item))
            if sending.key == entry.id {
                DeskWorkingLine(text: "Removing it…")
            } else {
                actions {
                    Button("Move") { moving = item }
                        .fontWeight(.semibold)
                        .foregroundStyle(.ariBone)
                    Button("Remove") { removing = item }
                        .foregroundStyle(.ariSecondary)
                }
            }
        case .checkIn(let plan):
            quiet(plan.why)
            Text("\(PlanWords.repeats(plan)) · \(PlanWords.origin(plan))")
                .font(.caption)
                .foregroundStyle(.ariTertiary)
            if sending.key == entry.id {
                DeskWorkingLine(text: "Cancelling it…")
            } else {
                actions {
                    Button("Change") { editing = plan }
                        .fontWeight(.semibold)
                        .foregroundStyle(.ariBone)
                    Button("Cancel") { cancelling = plan }
                        .foregroundStyle(.ariSecondary)
                }
            }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.ariSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actions(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack(spacing: 18) { buttons() }
            .font(.footnote)
            .buttonStyle(.plain)
    }

    /// "Kumo planned 14:00 to 16:00", or "held" for a time it's keeping free.
    private func blockWords(_ item: CalendarItem) -> String {
        let lead = LeadName.current
        if item.allDay { return "\(lead)'s, all day." }
        let span =
            "\(item.start.date.formatted(DeskTime.time))–\(item.end.date.formatted(DeskTime.time))"
        return item.status == .hold ? "\(lead) is holding \(span)." : "\(lead) planned \(span)."
    }

    /// What it really was: the usual kinds of time, other than the guess, or your own words.
    private func choices(for item: CalendarItem, id: String) -> some View {
        let describes = describing == id
        return VStack(alignment: .leading, spacing: 8) {
            WrappingStack(spacing: 8) {
                ForEach(
                    DayReading.corrections.filter { $0 != item.guess?.activity }, id: \.rawValue
                ) {
                    activity in
                    GuessChoice(title: DayReading.name(activity)) {
                        answer(GuessAnswer(activity: activity), for: item, id: id)
                    }
                }
                GuessChoice(title: describes ? "Cancel" : "Something else…") {
                    sending.clearProblem()
                    describing = describes ? nil : id
                }
            }
            if describes {
                InlineField(
                    prompt: "What was it?", text: $words, button: "Save",
                    buttonLabel: "Save what it was", opensKeyboard: true, limit: 60
                ) {
                    let text = InlineField.trimmed(words)
                    if !text.isEmpty { answer(GuessAnswer(text: text), for: item, id: id) }
                }
                .transition(.opacity)
            }
        }
    }

    private func answer(_ answer: GuessAnswer, for item: CalendarItem, id: String) {
        act(id, failure: "Couldn't tell \(LeadName.current)") {
            try await session.answerGuess(item.id, answer)
        }
    }

    /// Sends one change, with its row's spinner, and folds the row once it's gone through.
    private func act(
        _ id: String, failure: String = "Couldn't do that",
        _ deliver: @escaping () async throws -> Void
    ) {
        Task {
            unfolded = id
            if await sending.send(id, failure: failure, deliver) {
                unfolded = nil
                correcting = nil
                describing = nil
                words = ""
            }
        }
    }

    /// The first guess, open or with its choices, from `ARI_GUESS`, for stills.
    private func showGuess() {
        guard let shownGuess, unfolded == nil else { return }
        let first = days(now: .now).flatMap(\.entries).first {
            if case .guess = $0 { return true }
            return false
        }
        guard let first else { return }
        unfolded = first.id
        if shownGuess == .correct { correcting = first.id }
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

/// One of Kumo's blocks, to move: a new start, keeping its length.
private struct BlockMoveSheet: View {
    let item: CalendarItem
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var saving = false
    @State private var problem: String?

    init(item: CalendarItem, session: Session) {
        self.item = item
        self.session = session
        _start = State(initialValue: item.start.date)
    }

    private var length: TimeInterval { max(60, item.end.date.timeIntervalSince(item.start.date)) }

    /// The box moves a block by up to 12 hours either way.
    private var reach: ClosedRange<Date> {
        item.start.date.addingTimeInterval(
            -12 * 3600)...item.start.date.addingTimeInterval(12 * 3600)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Starts", selection: $start, in: reach,
                        displayedComponents: [.date, .hourAndMinute])
                    LabeledContent(
                        "Ends", value: start.addingTimeInterval(length).formatted(DeskTime.time))
                } footer: {
                    Text(
                        problem
                            ?? "It keeps its length, within 12 hours of where it was. You can undo it from Done."
                    )
                }
                .listRowBackground(Color.ariSurface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Move") { Task { await move() } }
                            .disabled(abs(start.timeIntervalSince(item.start.date)) < 60)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .tint(.ariText)
    }

    private func move() async {
        saving = true
        problem = nil
        defer { saving = false }
        do {
            let times = EventMove(
                start: Timestamp(start), end: Timestamp(start.addingTimeInterval(length)))
            try await session.move(item.id, to: times)
            dismiss()
        } catch {
            problem = "Couldn't move it: \(DeskSending.words(for: error))"
        }
    }
}
