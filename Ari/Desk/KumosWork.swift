import AriKit
import SwiftUI

/// Kumo's day of work, the state of play: what came in, what needs you, what it handled and what it
/// cleared, and how much it checks with you for each kind of work. Hidden by default, opened by
/// tapping Kumo's face or Done.
struct KumoLedger: Equatable {
    /// Everything on Kumo's plate today: what needs you, and what it handled and cleared.
    let came: Int
    /// The cards waiting on you.
    let needYou: [DeskCard]
    /// What Kumo did, each with its reason.
    let handled: [DoneEntry]
    /// What Kumo cleared with nothing needed, each with its reason.
    let cleared: [DoneEntry]
    /// How much Kumo checks with you, for each kind of work it has done.
    var trust: [Trust] = []
    /// Set when the ledger shows only some of a day's calls, such as yesterday's sorting to glance
    /// at while Kumo is learning: the day's name, such as "Yesterday".
    var focus: String?

    /// How far Kumo has come on one kind of work: Learning, then Spot checks, then Trusted. A
    /// correction steps it back one.
    struct Trust: Identifiable, Equatable {
        var id: String { kind }
        let kind: String
        let symbol: String
        let step: Step
        /// Kumo's line on where it stands, such as "Two weeks without a correction on sorting."
        let line: String
        /// The kind of work, for "Show me everything again".
        var work: WorkKind?

        enum Step: Int, CaseIterable {
            case learning, spotChecks, trusted

            var name: String {
                switch self {
                case .learning: "Learning"
                case .spotChecks: "Spot checks"
                case .trusted: "Trusted"
                }
            }
        }
    }
}

extension KumoLedger {
    /// Today's work as the box sends it, with what's waiting on you from the Desk.
    init(work: KumoWork, waiting: [DeskCard]) {
        self.init(
            came: waiting.count + work.handled.count + work.cleared.count, needYou: waiting,
            handled: work.handled, cleared: work.cleared, trust: work.trust.map(Trust.init))
    }

    /// A day's calls of some kinds of work only, to glance at: nothing waiting, and the ladder for
    /// those kinds alone.
    init(work: KumoWork, only kinds: [WorkKind], focus: String) {
        let handled = work.handled.filter { $0.work.map(kinds.contains) == true }
        let cleared = work.cleared.filter { $0.work.map(kinds.contains) == true }
        self.init(
            came: handled.count + cleared.count, needYou: [], handled: handled, cleared: cleared,
            trust: work.trust.filter { kinds.contains($0.work) }.map(Trust.init), focus: focus)
    }

    /// Whether the cleared mail opens unfolded: while Kumo is still learning to sort, or when
    /// you're glancing at a day's calls.
    var showsClearedAtFirst: Bool {
        focus != nil || trust.contains { $0.work == .sorting && $0.step == .learning }
    }
}

extension KumoLedger.Trust {
    /// A kind of work on the ladder, as the box sends it.
    init(_ rung: TrustRung) {
        self.init(
            kind: rung.title, symbol: Self.symbol(for: rung.work),
            step: Step(rawValue: rung.step.rung) ?? .learning, line: rung.line, work: rung.work)
    }

    /// Each kind of work's symbol, and a plain one for a kind Ari doesn't know yet.
    static func symbol(for work: WorkKind) -> String {
        switch work {
        case .sorting: "tray"
        case .calendar: "calendar"
        case .drafts: "envelope"
        case .contacts: "person.crop.circle"
        default: "circle.dashed"
        }
    }
}

struct KumosWorkView: View {
    let ledger: KumoLedger
    var openCard: (DeskCard) -> Void = { _ in }
    var undo: (DoneEntry) -> Void = { _ in }
    /// "That was wrong", which Kumo learns from.
    var wrong: ((DoneEntry) -> Void)?
    /// "Show me everything again", for one kind of work on the ladder.
    var showEverything: ((WorkKind) -> Void)?
    /// Opens everything Kumo has done, back before today.
    var openAll: (() -> Void)?
    /// An undo that didn't go through.
    var problem: String?
    /// A "Show me everything again" that didn't go through, shown with the ladder.
    var trustProblem: String?
    /// Opens scrolled down to how much Kumo checks with you, for previews.
    var opensAtTrust = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 44
    @State private var showsCleared: Bool?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    summary
                    if !ledger.needYou.isEmpty { needYou }
                    if !ledger.handled.isEmpty { handled }
                    if !ledger.cleared.isEmpty { cleared }
                    if !ledger.trust.isEmpty { trust.id("trust") }
                    if let openAll { allDone(openAll) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: Rhythm.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { if opensAtTrust { proxy.scrollTo("trust", anchor: .bottom) } }
        }
        .background(.ariBackground)
        .navigationTitle("\(LeadName.current)'s work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.foregroundStyle(.ariText)
            }
        }
    }

    // MARK: Today

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeskSectionLabel(ledger.focus ?? "Today")
            Group {
                if ledger.focus != nil {
                    Text(
                        "\(count(ledger.handled.count)) handled, \(count(ledger.cleared.count)) cleared. Tap That was wrong on any I got wrong."
                    )
                } else {
                    Text(
                        "\(count(ledger.came)) in: \(count(ledger.needYou.count)) need you, \(count(ledger.handled.count)) handled, \(count(ledger.cleared.count)) cleared."
                    )
                }
            }
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
            if let problem { DeskProblemLine(text: problem) }
            ForEach(ledger.handled) { entry in entryRow(entry) }
        }
    }

    /// Everything Kumo has done, back before today, where a reply to a line corrects it.
    private func allDone(_ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 4) {
                Text("Everything I've done")
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .foregroundStyle(.ariSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every day's Done, where you can tell me when I got one wrong")
    }

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
                    Label("Noted. I'll do it differently.", systemImage: "checkmark")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .labelStyle(NotedLabelStyle())
                        .padding(.top, 4)
                } else if entry.undo || wrong != nil {
                    HStack(spacing: 18) {
                        if entry.undo {
                            Button("Undo") { undo(entry) }
                                .fontWeight(.semibold)
                                .foregroundStyle(.ariBone)
                                .accessibilityLabel("Undo: \(entry.text)")
                        }
                        if let wrong {
                            Button("That was wrong") { wrong(entry) }
                                .foregroundStyle(.ariSecondary)
                                .accessibilityLabel("That was wrong: \(entry.text)")
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The cleared mail, folded: with sorting trusted, it stays out of the way unless you look.
    private var cleared: some View {
        let isOpen = showsCleared ?? ledger.showsClearedAtFirst
        return VStack(alignment: .leading, spacing: 12) {
            DeskSectionLabel("Cleared", trailing: "\(ledger.cleared.count)")
            Button {
                withAnimation(.smooth(duration: 0.3)) { showsCleared = !isOpen }
            } label: {
                HStack(spacing: 6) {
                    Text("\(ledger.cleared.count) read, nothing needed")
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
                    ForEach(ledger.cleared) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(
                                "\(Text(entry.text).foregroundStyle(.ariSecondary))\(Text(entry.reason.map { "  ·  \($0)" } ?? "").foregroundStyle(.ariTertiary))"
                            )
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if entry.isCorrected {
                                Text("Noted")
                                    .font(.footnote)
                                    .foregroundStyle(.ariTertiary)
                            } else if let wrong {
                                Button("That was wrong") { wrong(entry) }
                                    .font(.footnote)
                                    .foregroundStyle(.ariTertiary)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("That was wrong: \(entry.text)")
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color.ariLine).frame(width: 1) }
                .transition(.opacity)
            }
        }
    }

    // MARK: Trust

    private var trust: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeskSectionLabel("How much I check with you")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(ledger.trust.enumerated()), id: \.element.id) { index, trust in
                    if index > 0 { Divider().overlay(Color.ariLine) }
                    TrustRow(trust: trust, showEverything: showEverything)
                }
            }
            .deskCard()
            if let trustProblem { DeskProblemLine(text: trustProblem) }
            Text(
                "Learning: I show you everything. Spot checks: about one in five. Trusted: only what needs you. A “That was wrong” steps it back one."
            )
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One kind of work on the ladder: its name and step, three short rungs filled to where it stands,
/// and Kumo's line on why.
private struct TrustRow: View {
    let trust: KumoLedger.Trust
    var showEverything: ((WorkKind) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label(trust.kind, systemImage: trust.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .labelStyle(TrustLabelStyle())
                    Spacer(minLength: 8)
                    Text(trust.step.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.ariBone)
                }
                HStack(spacing: 4) {
                    ForEach(KumoLedger.Trust.Step.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step.rawValue <= trust.step.rawValue ? Color.ariBone : .ariLine)
                            .opacity(step.rawValue <= trust.step.rawValue ? 0.85 : 1)
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
                Text(trust.line)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.ariText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(trust.kind): \(trust.step.name). \(trust.line)")
            if let showEverything, let work = trust.work, trust.step != .learning {
                Button("Show me everything again") { showEverything(work) }
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .buttonStyle(.plain)
                    .accessibilityHint("\(trust.kind) goes back to Learning")
            }
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

/// The kind's symbol in bone, beside its name.
private struct TrustLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(.ariBone)
            configuration.title
        }
    }
}

/// Kumo's work today, from the box: it loads when it opens, and again after an Undo, a "That was
/// wrong" or "Show me everything again". A card that needs you opens in place; everything Kumo has
/// done before today is a step further. With a review card's day and kinds, it shows just those
/// calls to glance at.
struct KumosWorkScreen: View {
    let session: Session
    var review: ReviewCard?
    /// Opens scrolled down to how much Kumo checks with you.
    var opensAtTrust = false
    /// Opens with "That was wrong" asked of the first thing Kumo did, for a still.
    var asksWrongAtFirst = false

    @State private var work: KumoWork?
    @State private var problem: String?
    @State private var trustProblem: String?
    @State private var openedCard: DeskCard?
    @State private var showsAll = false
    @State private var correcting: DoneEntry?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .task {
                await load()
                if asksWrongAtFirst { correcting = work?.handled.first }
            }
            .sheet(item: $correcting) { entry in
                ThatWasWrong(entry: entry) { words in
                    try await session.correct(entry.id, text: words)
                    await load()
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { openedCard != nil }, set: { if !$0 { openedCard = nil } })
            ) {
                if let card = openedCard { cardView(card) }
            }
            .navigationDestination(isPresented: $showsAll) { AllDoneView(session: session) }
    }

    @ViewBuilder
    private var content: some View {
        if let work {
            KumosWorkView(
                ledger: ledger(work), openCard: { openedCard = $0 },
                undo: { entry in Task { await undo(entry) } },
                wrong: { correcting = $0 },
                showEverything: { kind in Task { await showEverything(kind) } },
                openAll: review == nil ? { showsAll = true } : nil, problem: problem,
                trustProblem: trustProblem, opensAtTrust: opensAtTrust)
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
        guard let review else {
            return KumoLedger(work: work, waiting: session.desk?.waiting ?? [])
        }
        let day = LocalTime(review.day).map { DayLabel.describe($0.date, time: false) }
        return KumoLedger(work: work, only: review.work, focus: day ?? review.day)
    }

    private func load() async {
        do {
            work = try await session.work(day: review?.day)
            problem = nil
        } catch {
            problem =
                "Couldn't load \(review == nil ? "today's" : "that day's") work: \(DeskSending.words(for: error))"
        }
    }

    private func showEverything(_ kind: WorkKind) async {
        trustProblem = nil
        do {
            try await session.resetTrust(kind)
            await load()
        } catch {
            trustProblem = "Couldn't change that: \(DeskSending.words(for: error))"
        }
    }

    private func undo(_ entry: DoneEntry) async {
        do {
            try await session.undo(entry.id)
            await load()
        } catch {
            problem = "Couldn't undo that: \(DeskSending.words(for: error))"
        }
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
