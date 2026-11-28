import AriKit
import SwiftUI

/// The shape every detail behind a line shares: what it is, in serif, when, a few labelled
/// paragraphs, and what you can do about it, one tap in.
struct DetailSheetLayout<Actions: View>: View {
    let title: String
    let when: String
    var sections: [(label: String, text: String)] = []
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(when)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                }
                ForEach(sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        DeskSectionLabel(sections[index].label)
                        Text(sections[index].text)
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                actions()
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .frame(maxWidth: Rhythm.column, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
    }
}

/// Undo and "That was wrong" for something Kumo did, as a detail sheet has them: two pills, a line
/// on what Undo does, and "That was wrong" opening right under them, as it does everywhere.
struct WorkActions: View {
    /// The entry in Kumo's work, as far as it's known.
    let entry: DoneEntry
    /// What Undo will do, in a line.
    var undoes: String?
    let undo: () async throws -> Void
    let correct: (String?) async throws -> Void

    @State private var correcting = false
    @State private var undoing = false
    @State private var problem: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entry.isCorrected {
                Label("Noted. I'll do it differently.", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            } else if !correcting {
                HStack(spacing: 10) {
                    if entry.undo {
                        DeskPill(title: "Undo", busy: undoing, label: "Undo: \(entry.text)") {
                            Task { await performUndo() }
                        }
                        .disabled(undoing)
                    }
                    DeskPill(title: "That was wrong", label: "That was wrong: \(entry.text)") {
                        problem = nil
                        correcting = true
                    }
                    .disabled(undoing)
                }
                .waitsForConnection()
                if entry.undo, let undoes {
                    Text(undoes)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let problem { DeskProblemLine(text: problem) }
            if correcting {
                ThatWasWrong(
                    entry: entry,
                    send: { words in
                        try await correct(words)
                        correcting = false
                    },
                    cancel: { correcting = false }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
        .animation(.smooth(duration: 0.3), value: correcting)
    }

    private func performUndo() async {
        undoing = true
        problem = nil
        defer { undoing = false }
        do {
            try await undo()
        } catch is CancellationError {
        } catch {
            problem = "Couldn't undo it: \(DeskSending.words(for: error))"
        }
    }
}

// MARK: - A line of the dream

/// A line from the dream, opened: what Kumo did, when in which dream, why where Kumo said, and Undo
/// and "That was wrong" for a line that changed something.
struct DreamLineDetail: View {
    let line: DreamLine
    let dream: Dream

    @Environment(Dreams.self) private var dreams: Dreams?
    @State private var entry: DoneEntry?

    var body: some View {
        DetailSheetLayout(title: line.text, when: when, sections: sections) {
            if line.undone {
                Label("Taken back.", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            } else if let done = line.done {
                WorkActions(
                    entry: shownEntry(done),
                    undoes: "Undo puts it back as it was before the dream.",
                    undo: {
                        if let undone = try await dreams?.undo(line) { entry = undone }
                    },
                    correct: { words in
                        if let corrected = try await dreams?.correct(line, text: words) {
                            entry = corrected
                        }
                    })
            }
        }
        .task { entry = await dreams?.entry(for: line) }
    }

    /// The entry as far as it's known: read from Done, or, until then, the line itself.
    private func shownEntry(_ done: DoneID) -> DoneEntry {
        entry
            ?? DoneEntry(
                id: done, at: dream.endedAt, text: line.text, undo: line.undo,
                dream: dream.id)
    }

    /// "Planned in last night's dream · 04:12", or "in the dream you asked for" for Dream now.
    private var when: String {
        let verb: String =
            switch line.group.shown {
            case .planned: "Planned"
            case .tidied: "Tidied"
            case .saved: "Saved for you"
            default: "Noticed"
            }
        let which = dream.trigger == .manual ? "the dream you asked for" : "last night's dream"
        return "\(verb) in \(which) · \(dream.endedAt.date.formatted(DeskTime.time))"
    }

    private var sections: [(label: String, text: String)] {
        guard let reason = entry?.reason, !reason.isEmpty else { return [] }
        return [("Why", reason)]
    }
}

// MARK: - Something Kumo did

/// Something Kumo did today, opened: when, why, where to see it, and Undo and "That was wrong".
struct DoneDetail: View {
    let entry: DoneEntry
    let undo: (DoneEntry) async throws -> DoneEntry
    let correct: (DoneEntry, String?) async throws -> DoneEntry

    @State private var shown: DoneEntry?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let entry = shown ?? entry
        DetailSheetLayout(
            title: entry.text, when: "Done at \(entry.at.date.formatted(DeskTime.time))",
            sections: entry.reason.map { [("Why", $0)] } ?? []
        ) {
            if let mail = entry.mail, let url = DraftCardView.mailURL(messageID: mail.messageID) {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Text("See it in Mail")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                }
                .buttonStyle(.plain)
            }
            WorkActions(
                entry: entry,
                undo: { shown = try await undo(entry) },
                correct: { words in shown = try await correct(entry, words) })
        }
    }
}

// MARK: - One of Kumo's plans

/// One of Kumo's plans, opened: when, why, what Kumo will do, the times a repeat comes next on a
/// dotted line, and Move…, Skip, Stop or Cancel.
struct PlanDetail: View {
    let plan: WakeUp
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmsStop = false
    @State private var sending = DeskSending()

    var body: some View {
        DetailSheetLayout(
            title: plan.shownTitle, when: when,
            sections: [("Why", plan.why), ("What I'll do", plan.what)]
        ) {
            if plan.repeat != nil { comingUp }
            HStack(spacing: 10) {
                DeskPill(title: "Move…") { editing = true }
                if plan.repeat != nil {
                    // One time only: it comes back at the time after, or ends if this was its last.
                    DeskPill(title: skipTitle, busy: sending.key == "skip") {
                        Task {
                            await sending.send("skip", failure: "Couldn't skip it") {
                                try await session.skip(plan.id)
                            }
                        }
                    }
                }
                DeskPill(title: stopTitle, busy: sending.key == "stop") {
                    confirmsStop = true
                }
            }
            .disabled(sending.isSending)
            .waitsForConnection()
            if let problem = sending.problem { DeskProblemLine(text: problem) }
        }
        .sheet(isPresented: $editing) { PlanEditor(plan: plan, session: session) }
        .confirmationDialog(
            plan.repeat == nil ? "Cancel “\(plan.shownTitle)”?" : "Stop “\(plan.shownTitle)”?",
            isPresented: $confirmsStop, titleVisibility: .visible
        ) {
            Button(plan.repeat == nil ? "Cancel the plan" : "Stop every time", role: .destructive) {
                Task {
                    let stopped = await sending.send("stop", failure: "Couldn't stop it") {
                        try await session.cancel(plan.id)
                    }
                    if stopped { dismiss() }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("\(LeadName.current) won't set it again unless you ask.")
        }
        // Moved, skipped or changed elsewhere: once it's gone from the plans, so is this.
        .onChange(of: session.desk?.plans.contains { $0.id == plan.id }) { _, still in
            if still == false { dismiss() }
        }
    }

    /// "Tuesdays at 23:45 · 4 left", or "Today at 18:45" for a one-off.
    private var when: String {
        if let repeating = plan.repeat {
            return PlanWords.ending(
                "\(PlanWords.repeats(repeating)) at \(repeating.time)", repeating)
        }
        let day = PlanWords.day(plan.at.date, now: DeskClock.now()) ?? "Today"
        return "\(day) at \(plan.at.date.formatted(DeskTime.time))"
    }

    /// "Cancel it" for a one-off; for a repeat, "Stop it", or "Stop all four" when it counts down.
    private var stopTitle: String {
        guard let repeating = plan.repeat else { return "Cancel it" }
        guard let left = repeating.left, left > 1 else { return "Stop it" }
        let words = ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return "Stop all \(left <= 10 ? words[left - 2] : "\(left)")"
    }

    private var skipTitle: String {
        Calendar.current.isDate(plan.at.date, inSameDayAs: DeskClock.now())
            ? (Calendar.current.component(.hour, from: plan.at.date) >= 18
                ? "Skip tonight" : "Skip today")
            : "Skip the next one"
    }

    /// The next four times, on a dotted line.
    private var comingUp: some View {
        let times = PlanReading.nextTimes(of: plan)
        return VStack(alignment: .leading, spacing: 10) {
            DeskSectionLabel("Coming up")
            HStack(spacing: 0) {
                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(index == 0 ? Color.ariText : .ariSecondary.opacity(0.6))
                            .frame(width: index == 0 ? 8 : 6, height: index == 0 ? 8 : 6)
                        Text(Self.name(time))
                            .font(.caption2)
                            .foregroundStyle(index == 0 ? Color.ariSecondary : .ariTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                DottedRule().frame(height: 2).padding(.top, 3).padding(.horizontal, 30)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Tonight", "Today", or "8 Dec".
    private static func name(_ time: Date) -> String {
        let now = DeskClock.now()
        if Calendar.current.isDate(time, inSameDayAs: now) {
            return Calendar.current.component(.hour, from: time) >= 18 ? "Tonight" : "Today"
        }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now),
            Calendar.current.isDate(time, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        return time.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A faint dotted line, as the Desk's day thread draws the hours ahead.
struct DottedRule: View {
    var body: some View {
        Canvas { canvas, size in
            var dots = Path()
            for x in stride(from: 0, through: size.width, by: 5) {
                dots.addEllipse(
                    in: CGRect(x: x - 0.8, y: size.height / 2 - 0.8, width: 1.6, height: 1.6))
            }
            canvas.fill(dots, with: .color(.ariTertiary.opacity(0.6)))
        }
        .accessibilityHidden(true)
    }
}
