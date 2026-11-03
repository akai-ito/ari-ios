import AriKit
import SwiftUI

/// Kumo's plans in words: when one is due, how it comes back, and who set it.
enum PlanWords {
    /// "18:45" today, "Tomorrow 08:30", or "Thu 12 14:00" further off.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(DeskTime.time)
        return day(date, now: now, calendar: calendar).map { "\($0) \(time)" } ?? time
    }

    /// "Tomorrow", or "Thu 12" further off; `nil` for today.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        return date.formatted(DeskTime.weekdayDay)
    }

    /// "Weekdays at 08:30", "Every day at 09:00", "Sat, Sun at 10:00", or "Once" for a one-off.
    static func repeats(_ plan: WakeUp) -> String {
        guard let repeating = plan.repeat else { return "Once" }
        return "\(days(repeating.days)) at \(repeating.time)"
    }

    static func days(_ days: [Weekday]) -> String {
        let set = Set(days)
        if set == Set(Weekday.known) { return "Every day" }
        if set == Set(Weekday.weekdays) { return "Weekdays" }
        if set == Set(Weekday.weekend) { return "Weekends" }
        let names = Weekday.known.filter(set.contains).map(name)
        return names.count == 1 ? "Every \(names[0])" : names.joined(separator: ", ")
    }

    /// "Mon" for Monday; a day Ari doesn't know as the box wrote it.
    static func name(_ day: Weekday) -> String {
        guard let index = Weekday.known.firstIndex(of: day) else { return day.rawValue }
        // The calendar's short names start on Sunday; the protocol's days start on Monday.
        return Calendar.current.shortWeekdaySymbols[(index + 1) % 7]
    }

    /// "You asked" or "Kumo's idea", and where it came from when that says more, such as "from
    /// Tess Harlow: Thursday's technical".
    static func origin(_ plan: WakeUp) -> String {
        let who = plan.by == .you ? "You asked" : "\(LeadName.current)'s idea"
        guard plan.source.kind != .chat, !plan.source.title.isEmpty else { return who }
        return "\(who), from \(plan.source.title)"
    }
}

/// One of Kumo's plans as a row: when, what it's for, why, how it comes back and who set it. A tap
/// opens it to change or cancel.
struct PlanRow: View {
    let plan: WakeUp
    let open: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 46
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: open) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
            layout {
                Text(plan.at.date, format: DeskTime.time)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.ariTertiary)
                    .frame(minWidth: timeWidth, alignment: .leading)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.what)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                    Text(plan.why)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(2)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.ariTertiary.opacity(0.85))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change or cancel it")
    }

    /// "Tomorrow · Weekdays at 08:30 · You asked": the day when it isn't today, how it comes back,
    /// and who set it.
    private var meta: String {
        let day = PlanWords.day(plan.at.date)
        return ([day, PlanWords.repeats(plan), PlanWords.origin(plan)].compactMap { $0 })
            .joined(separator: " · ")
    }
}

/// One of Kumo's plans, opened: change when it's next due and what it's for, make a repeating one a
/// one-off, or cancel it. Saving sends only what changed.
struct PlanEditor: View {
    let plan: WakeUp
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var what: String
    @State private var at: Date
    @State private var oneOff = false
    @State private var saving = false
    @State private var cancelling = false
    @State private var confirmsCancel = false
    @State private var problem: String?

    init(plan: WakeUp, session: Session) {
        self.plan = plan
        self.session = session
        _what = State(initialValue: plan.what)
        _at = State(initialValue: plan.at.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it's for", text: $what, axis: .vertical)
                        .lineLimit(1...3)
                    DatePicker(
                        plan.repeat == nil ? "When" : "Next time", selection: $at,
                        in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    if plan.repeat != nil {
                        Toggle("Just this once", isOn: $oneOff)
                    }
                } footer: {
                    Text(problem ?? footer)
                }
                .listRowBackground(Color.ariSurface)
                Section {
                    LabeledContent("Why", value: plan.why)
                    LabeledContent("Set", value: PlanWords.origin(plan))
                }
                .listRowBackground(Color.ariSurface)
                .foregroundStyle(.ariSecondary)
                Section {
                    Button("Cancel this plan", role: .destructive) { confirmsCancel = true }
                        .disabled(cancelling || saving)
                }
                .listRowBackground(Color.ariSurface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle("\(LeadName.current)'s plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(change == nil || trimmed.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                "Cancel “\(plan.what)”?", isPresented: $confirmsCancel, titleVisibility: .visible
            ) {
                Button("Cancel the plan", role: .destructive) { Task { await cancel() } }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("\(LeadName.current) won't set it again unless you ask.")
            }
        }
        .presentationDetents([.medium, .large])
        .tint(.ariText)
    }

    private var trimmed: String { what.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var footer: String {
        guard let repeating = plan.repeat else {
            return
                "\(LeadName.current) wakes up then, looks first, and messages you if it's useful."
        }
        return oneOff
            ? "It comes once, at the time above, and no more."
            : "Only the next time moves; it still comes back "
                + "\(PlanWords.days(repeating.days).lowercased()) at \(repeating.time)."
    }

    /// What you changed, or `nil` for nothing.
    private var change: WakeUpChange? {
        var change = WakeUpChange()
        if trimmed != plan.what { change.what = trimmed }
        if abs(at.timeIntervalSince(plan.at.date)) >= 60 { change.at = Timestamp(at) }
        if oneOff { change.repeat = .some(nil) }
        return change == WakeUpChange() ? nil : change
    }

    private func save() async {
        guard let change else { return }
        saving = true
        problem = nil
        defer { saving = false }
        do {
            try await session.change(plan.id, change)
            dismiss()
        } catch {
            problem = "Couldn't change it: \(DeskSending.words(for: error))"
        }
    }

    private func cancel() async {
        cancelling = true
        problem = nil
        defer { cancelling = false }
        do {
            try await session.cancel(plan.id)
            dismiss()
        } catch {
            problem = "Couldn't cancel it: \(DeskSending.words(for: error))"
        }
    }
}
