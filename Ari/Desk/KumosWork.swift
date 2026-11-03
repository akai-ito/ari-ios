import AriKit
import SwiftUI

/// Kumo's day of work, the state of play: what came in, what needs you, what it handled and what it
/// cleared. Hidden by default, opened by tapping Kumo's face or Done.
struct KumoLedger: Equatable {
    /// Everything on Kumo's plate today: what needs you, and what it handled and cleared.
    let came: Int
    /// The cards waiting on you.
    let needYou: [DeskCard]
    /// What Kumo did, each with its reason.
    let handled: [DoneEntry]
    /// What Kumo cleared with nothing needed, each with its reason.
    let cleared: [DoneEntry]
}

extension KumoLedger {
    /// Today's work as the box sends it, with what's waiting on you from the Desk.
    init(work: KumoWork, waiting: [DeskCard]) {
        self.init(
            came: waiting.count + work.handled.count + work.cleared.count, needYou: waiting,
            handled: work.handled, cleared: work.cleared)
    }
}

/// How far back Kumo's work has been read: more to come as you scroll, a day that didn't load, or
/// the beginning.
enum EarlierWork: Equatable {
    /// Reads the next earlier day when the bottom comes into view; `attempt` goes up after each, so
    /// it reads again if the bottom is still in view.
    case more(attempt: Int)
    case failed(String)
    case finished
}

/// Kumo's work: today's state of play, then every earlier day as you scroll back, the only log of
/// what Kumo did. Each thing done has its reason, Undo where it can be undone, and "That was
/// wrong", which opens right under it.
struct KumosWorkView: View {
    let ledger: KumoLedger
    /// The days before today, newest first, as they're read.
    var earlier: [KumoWork] = []
    /// How far back it has read.
    var earlierWork: EarlierWork?
    /// Reads the next earlier day.
    var readEarlier: () async -> Void = {}
    /// Tries the day that didn't load again.
    var retryEarlier: () -> Void = {}
    var openCard: (DeskCard) -> Void = { _ in }
    var undo: (DoneEntry) async throws -> Void = { _ in }
    /// "That was wrong", with your words or none, which Kumo learns from.
    var correct: (DoneEntry, String?) async throws -> Void = { _, _ in }
    /// Opens with "That was wrong" asked of one entry, for a still.
    var correctingAtFirst: DoneID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 44
    /// Each day's cleared mail, shown or folded, by day; today's starts as the ledger says.
    @State private var clearedShown: [String: Bool] = [:]
    /// The entry with "That was wrong" open under it.
    @State private var correcting: DoneID?
    @State private var undoing: DoneID?
    @State private var undoProblem: UndoProblem?
    /// Whether the bottom, where the next day loads, is in view.
    @State private var bottomInView = false

    private struct UndoProblem: Equatable {
        let entry: DoneID
        let text: String
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    summary
                    if !ledger.needYou.isEmpty { needYou }
                    if !ledger.handled.isEmpty { handled }
                    if !ledger.cleared.isEmpty { cleared }
                    ForEach(earlier, id: \.day) { day in pastDay(day) }
                    if let earlierWork { bottom(earlierWork) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .task {
                // Once the sheet has settled, so the scroll to it takes.
                guard let correctingAtFirst else { return }
                try? await Task.sleep(for: .milliseconds(600))
                correcting = correctingAtFirst
            }
            // The field opens with the keyboard: keep the line it's about in view above it.
            .onChange(of: correcting) { _, entry in
                guard let entry else { return }
                Task {
                    // After the field has opened, so the scroll knows where the line now ends.
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        proxy.scrollTo(entry, anchor: .center)
                    }
                }
            }
        }
        .background(.ariBackground)
        .navigationTitle("\(LeadName.current)'s work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.foregroundStyle(.ariText)
            }
        }
        .animation(.smooth(duration: 0.3), value: correcting)
    }

    // MARK: Today

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeskSectionLabel("Today")
            Text(
                "\(count(ledger.came)) in: \(count(ledger.needYou.count)) need you, \(count(ledger.handled.count)) handled, \(count(ledger.cleared.count)) cleared."
            )
            .font(.system(.title3, design: .serif))
            .foregroundStyle(.ariText)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func count(_ number: Int) -> Text {
        Text("\(number)").fontWeight(.semibold).monospacedDigit()
    }

    private var needYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeskSectionLabel("Need you", trailing: "\(ledger.needYou.count)")
            ForEach(ledger.needYou) { card in
                Button {
                    openCard(card)
                } label: {
                    HStack(spacing: 12) {
                        CardSymbol(kind: card.kind)
                        Text(card.title)
                            .font(.subheadline)
                            .foregroundStyle(.ariText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariTertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens it")
            }
        }
    }

    private var handled: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeskSectionLabel("Handled", trailing: "\(ledger.handled.count)")
            ForEach(ledger.handled) { entry in entryRow(entry) }
        }
    }

    /// Today's cleared mail, folded: it stays out of the way unless you look.
    private var cleared: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeskSectionLabel("Cleared", trailing: "\(ledger.cleared.count)")
            clearedFold(ledger.cleared, day: "today", shownAtFirst: false)
        }
    }

    // MARK: Earlier days

    /// A day before today: what Kumo did, then the mail it read with nothing needed, folded.
    private func pastDay(_ work: KumoWork) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            DeskSectionLabel(Self.name(of: work.day))
            ForEach(work.handled) { entry in entryRow(entry) }
            if !work.cleared.isEmpty {
                clearedFold(work.cleared, day: work.day, shownAtFirst: false)
            }
        }
    }

    /// The bottom of what's read: the next day reads as it comes into view, or says why it didn't.
    @ViewBuilder
    private func bottom(_ earlierWork: EarlierWork) -> some View {
        switch earlierWork {
        case .more(let attempt):
            ProgressView()
                .tint(.ariSecondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Loading earlier days")
                .onScrollVisibilityChange(threshold: 0.1) { bottomInView = $0 }
                // Again after each day, while the bottom is still in view.
                .task(id: Reading(attempt: attempt, inView: bottomInView)) {
                    if bottomInView { await readEarlier() }
                }
        case .failed(let text):
            VStack(alignment: .leading, spacing: 8) {
                DeskProblemLine(text: text)
                DeskPill(title: "Try again", label: "Try loading earlier days again") {
                    retryEarlier()
                }
            }
        case .finished:
            EmptyView()
        }
    }

    private struct Reading: Equatable {
        let attempt: Int
        let inView: Bool
    }

    /// "Yesterday", or the weekday and date, such as "Monday 2 November".
    static func name(of day: String) -> String {
        guard let date = LocalTime(day)?.date else { return day }
        return DayLabel.describe(date, time: false)
    }

    // MARK: Entries

    /// One thing Kumo did: when, what, and why, with Undo where it can be undone and "That was
    /// wrong", which Kumo learns from.
    private func entryRow(_ entry: DoneEntry) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(entry.at.date, format: DeskTime.time)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.ariTertiary)
                .frame(minWidth: timeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = entry.reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.isCorrected {
                    noted.padding(.top, 4)
                } else if correcting != entry.id {
                    HStack(spacing: 18) {
                        if entry.undo { undoButton(entry) }
                        wrongButton(entry)
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                }
                if let undoProblem, undoProblem.entry == entry.id {
                    DeskProblemLine(text: undoProblem.text)
                }
                if correcting == entry.id { correction(entry) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(entry.id)
    }

    private var noted: some View {
        Label("Noted. I'll do it differently.", systemImage: "checkmark")
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
            .labelStyle(NotedLabelStyle())
    }

    @ViewBuilder
    private func undoButton(_ entry: DoneEntry) -> some View {
        if undoing == entry.id {
            ProgressView()
                .controlSize(.small)
                .tint(.ariSecondary)
                .accessibilityLabel("Undoing")
        } else {
            Button("Undo") { Task { await performUndo(entry) } }
                .fontWeight(.semibold)
                .foregroundStyle(.ariBone)
                .buttonStyle(.plain)
                .disabled(undoing != nil)
                .accessibilityLabel("Undo: \(entry.text)")
        }
    }

    private func wrongButton(_ entry: DoneEntry) -> some View {
        Button("That was wrong") {
            undoProblem = nil
            correcting = entry.id
        }
        .foregroundStyle(.ariSecondary)
        .buttonStyle(.plain)
        .accessibilityLabel("That was wrong: \(entry.text)")
    }

    /// "That was wrong", open under the line it's about.
    private func correction(_ entry: DoneEntry) -> some View {
        ThatWasWrong(
            entry: entry,
            send: { words in
                try await correct(entry, words)
                correcting = nil
            },
            cancel: { correcting = nil }
        )
        .padding(.top, 6)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private func performUndo(_ entry: DoneEntry) async {
        guard undoing == nil else { return }
        undoing = entry.id
        undoProblem = nil
        defer { undoing = nil }
        do {
            try await undo(entry)
        } catch is CancellationError {
        } catch {
            undoProblem = UndoProblem(
                entry: entry.id, text: "Couldn't undo it: \(DeskSending.words(for: error))")
        }
    }

    /// A day's mail read with nothing needed, folded into one line that opens to each, with why.
    private func clearedFold(_ entries: [DoneEntry], day: String, shownAtFirst: Bool) -> some View {
        let isOpen = clearedShown[day] ?? shownAtFirst
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    clearedShown[day] = !isOpen
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(entries.count) read, nothing needed")
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                    Chevron(isOpen: isOpen)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Shown" : "Folded")
            .accessibilityHint(isOpen ? "Folds them" : "Shows each, with why")
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in clearedRow(entry) }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color.ariLine).frame(width: 1) }
                .transition(.opacity)
            }
        }
    }

    private func clearedRow(_ entry: DoneEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let line = Text(
                "\(Text(entry.text).foregroundStyle(.ariSecondary))\(Text(entry.reason.map { "  ·  \($0)" } ?? "").foregroundStyle(.ariTertiary))"
            )
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            if typeSize.isAccessibilitySize {
                line
                clearedActions(entry)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    line
                    Spacer(minLength: 8)
                    clearedActions(entry)
                }
            }
            if let undoProblem, undoProblem.entry == entry.id {
                DeskProblemLine(text: undoProblem.text)
            }
            if correcting == entry.id { correction(entry) }
        }
        .id(entry.id)
    }

    @ViewBuilder
    private func clearedActions(_ entry: DoneEntry) -> some View {
        if entry.isCorrected {
            Text("Noted").font(.footnote).foregroundStyle(.ariTertiary)
        } else if correcting != entry.id {
            HStack(spacing: 14) {
                if entry.undo { undoButton(entry) }
                wrongButton(entry).foregroundStyle(.ariTertiary)
            }
            .font(.footnote)
        }
    }
}

/// A small tick beside "Noted", in the tertiary colour.
private struct NotedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Kumo's work from the box: today loads when it opens, and again after an Undo or a "That was
/// wrong"; earlier days load as you scroll back. A card that needs you opens in place.
struct KumosWorkScreen: View {
    let session: Session
    /// Opens with "That was wrong" asked of the first thing Kumo did, for a still.
    var asksWrongAtFirst = false

    @State private var work: KumoWork?
    @State private var history = WorkHistory()
    /// Goes up after each earlier day read, or tried.
    @State private var attempts = 0
    @State private var historyProblem: String?
    @State private var problem: String?
    @State private var openedCard: DeskCard?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .task { await load() }
            .navigationDestination(
                isPresented: Binding(
                    get: { openedCard != nil }, set: { if !$0 { openedCard = nil } })
            ) {
                if let card = openedCard { cardView(card) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let work {
            KumosWorkView(
                ledger: ledger(work), earlier: history.days, earlierWork: earlierWork,
                readEarlier: readEarlier, retryEarlier: { historyProblem = nil },
                openCard: { openedCard = $0 }, undo: undo(_:), correct: correct(_:_:),
                correctingAtFirst: asksWrongAtFirst ? work.handled.first?.id : nil)
        } else {
            VStack(spacing: 12) {
                if let problem {
                    DeskProblemLine(text: problem)
                    DeskPill(title: "Try again") { Task { await load() } }
                } else {
                    ProgressView().tint(.ariSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(.ariBackground)
            .navigationTitle("\(LeadName.current)'s work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.ariText)
                }
            }
        }
    }

    private func ledger(_ work: KumoWork) -> KumoLedger {
        KumoLedger(work: work, waiting: session.desk?.waiting ?? [])
    }

    /// Earlier days, as far as they've been read.
    private var earlierWork: EarlierWork? {
        if let historyProblem { return .failed(historyProblem) }
        return history.isFinished ? .finished : .more(attempt: attempts)
    }

    private func load() async {
        do {
            work = try await session.work()
            problem = nil
        } catch {
            problem = "Couldn't load today's work: \(DeskSending.words(for: error))"
        }
    }

    /// The next earlier day with anything on it.
    private func readEarlier() async {
        guard let work, historyProblem == nil else { return }
        var next = history
        do throws(RequestError) {
            try await next.readNext(
                after: work,
                done: { before async throws(RequestError) in
                    try await session.done(before: before, limit: 1)
                },
                work: { day async throws(RequestError) in try await session.work(day: day) })
            history = next
        } catch {
            if case .network(.cancelled) = error { return }
            historyProblem = "Couldn't load earlier days: \(error.plainWords)"
        }
        attempts += 1
    }

    /// Takes one thing back: its line says so at once, wherever it is, and today follows.
    private func undo(_ entry: DoneEntry) async throws {
        show(try await session.undo(entry.id))
        await load()
    }

    /// "That was wrong": the line shows it's noted, and today follows.
    private func correct(_ entry: DoneEntry, _ words: String?) async throws {
        show(try await session.correct(entry.id, text: words))
        await load()
    }

    private func show(_ entry: DoneEntry) {
        work = work?.replacing(entry)
        history = history.replacing(entry)
    }

    /// A card that needs you, opened in full, as on the Desk, and kept as the Desk has it now.
    private func cardView(_ opened: DeskCard) -> some View {
        let card = session.desk?.waiting.first { $0.id == opened.id } ?? opened
        return ScrollView {
            DeskCardView(card: card, context: context(for: card)) { answer in
                try await session.answer(card.id, answer)
                openedCard = nil
            }
            .padding(16)
        }
        .background(.ariBackground)
        .navigationTitle(CardLook.name(card.kind))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The card's corner: the thing in motion it's about, such as "Job search".
    private func context(for card: DeskCard) -> String? {
        guard let motion = card.motion else { return nil }
        return session.motions?.all.first { $0.id == motion }?.title
    }
}
