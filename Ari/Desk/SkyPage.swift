import AriKit
import SwiftUI

/// What the moon or the sun opens: one page. While the night's dream is new it leads with Last
/// night, the weave's replay at the top and its lines in four groups (Planned, Tidied, Noticed,
/// Saved for you); once seen, it leads with Today, and the night folds into one line, unless you
/// asked for a dream today. Then today's plans and what's done, each line opening its detail, and
/// Dream now at the foot. Opening it while the dream is new marks it seen.
struct SkyPage: View {
    let session: Session
    /// What hung over Kumo's shoulder when you opened it.
    let sky: Sky
    #if DEBUG
        /// Opens a detail at once, or scrolls, for a still: `line`, `done`, `today` (a plan
        /// today), `plans`, `plan` (one on the Plans page), `wrong` or `lower`.
        var opensAtFirst: String?
    #endif

    @Environment(Dreams.self) private var dreams: Dreams?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var work: KumoWork?
    @State private var workProblem: String?
    @State private var path: [Route] = []
    @State private var detail: Detail?
    /// Whether the page led with the dream when it opened; it stays so while it's open.
    @State private var leads: Bool?
    @State private var showsNight = false
    @State private var watching = false
    @State private var material: (threads: [String], mail: Int) = ([], 0)
    @State private var dreamProblem: String?

    enum Route: Hashable {
        case plans
        case allWork
    }

    enum Detail: Identifiable {
        case line(DreamLine, Dream)
        case done(DoneEntry)
        case plan(WakeUp)

        var id: String {
            switch self {
            case .line(let line, let dream): "line \(dream.id) \(line.text)"
            case .done(let entry): "done \(entry.id)"
            case .plan(let plan): "plan \(plan.id)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        OfflineLine()
                        if let dream, leadsWithDream {
                            if dream.trigger == .manual {
                                manualLabel(dream)
                            } else {
                                WeaveReplayStrip(scene: scene(for: dream))
                            }
                            groups(dream)
                            hairline
                        } else if let dream {
                            folded(dream)
                        }
                        plans
                        done
                        dreamNow.id("foot")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .frame(maxWidth: Rhythm.column, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                #if DEBUG
                    .task {
                        guard opensAtFirst == "lower" else { return }
                        try? await Task.sleep(for: .milliseconds(900))
                        proxy.scrollTo("foot", anchor: .bottom)
                    }
                #endif
            }
            .background(.ariBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .plans: PlansPage(session: session)
                case .allWork:
                    #if DEBUG
                        KumosWorkScreen(session: session, asksWrongAtFirst: opensAtFirst == "wrong")
                    #else
                        KumosWorkScreen(session: session)
                    #endif
                }
            }
        }
        .sheet(item: $detail) { detail in
            Group {
                switch detail {
                case .line(let line, let dream): DreamLineDetail(line: line, dream: dream)
                case .done(let entry):
                    DoneDetail(entry: entry, undo: undo(_:), correct: correct(_:_:))
                case .plan(let plan): PlanDetail(plan: plan, session: session)
                }
            }
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ariBackground)
            .environment(dreams)
        }
        .fullScreenCover(isPresented: $watching) {
            WeaveScreen(session: session).environment(dreams)
        }
        .task {
            if leads == nil {
                leads = DreamReading.leadsWithDream(dreams?.latest, now: DeskClock.now())
            }
            await load()
        }
        .task { try? await session.refreshPlans() }
        .task(id: dream?.id) {
            guard let dream else { return }
            material = await WeaveSource.material(for: dream.day, session: session)
            // Seen once you've had a moment with it.
            try? await Task.sleep(for: .seconds(1.5))
            if dream.isNew { await dreams?.see(dream.id) }
        }
        #if DEBUG
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                switch opensAtFirst {
                case "line":
                    if let dream, let line = dream.lines.first { detail = .line(line, dream) }
                case "done": if let first = handled.first { detail = .done(first) }
                case "today":
                    if let plan = groups.today.first(where: { $0.repeat != nil })
                        ?? groups.today.first
                    {
                        detail = .plan(plan)
                    }
                case "plans", "plan": path = [.plans]
                case "wrong": path = [.allWork]
                default: break
                }
            }
        #endif
    }

    private var dream: Dream? { dreams?.latest }

    private var leadsWithDream: Bool {
        leads ?? DreamReading.leadsWithDream(dream, now: DeskClock.now())
    }

    private func isToday(_ dream: Dream) -> Bool {
        Calendar.current.isDate(dream.endedAt.date, inSameDayAs: DeskClock.now())
    }

    private func scene(for dream: Dream) -> WeaveScene {
        WeaveSource.scene(
            for: dream, threads: material.threads, mail: material.mail, session: session,
            now: DeskClock.now())
    }

    // MARK: Header

    private var header: some View {
        let night = leadsWithDream && dream?.trigger != .manual
        return HStack(spacing: 14) {
            SkyGlyph(sky: night ? .moon : (sky == .none || sky == .moon ? .sun : sky), side: 46)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(night ? "Last night" : "Today")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.ariText)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    night
                        ? dreamt(dream)
                        : DeskClock.now().formatted(.dateTime.weekday(.wide).day().month(.wide))
                )
                .font(.footnote)
                .foregroundStyle(.ariTertiary)
            }
        }
    }

    /// "Dreamt at 04:00 · while you slept", or "· you asked" for Dream now.
    private func dreamt(_ dream: Dream?) -> String {
        guard let dream else { return "" }
        let time = dream.startedAt.date.formatted(DeskTime.time)
        return "Dreamt at \(time) · \(dream.trigger == .manual ? "you asked" : "while you slept")"
    }

    private func manualLabel(_ dream: Dream) -> some View {
        HStack(spacing: 8) {
            SkyGlyph(sky: .moon, side: 20)
            Text("Dreamt at \(dream.startedAt.date.formatted(DeskTime.time))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ariSecondary)
            Text("· you asked").font(.footnote).foregroundStyle(.ariTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var hairline: some View {
        Rectangle().fill(Color.ariLine).frame(height: 1).padding(.vertical, -6)
    }

    // MARK: The dream

    private func groups(_ dream: Dream) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(dream.groups, id: \.group) { group in
                VStack(alignment: .leading, spacing: 12) {
                    DeskSectionLabel(Self.title(group.group))
                    ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                        DreamLineRow(line: line) { detail = .line(line, dream) }
                    }
                }
            }
            if dream.lines.isEmpty {
                Text(dream.headline ?? "A quiet night: nothing needed changing.")
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
            }
        }
    }

    /// Once seen, the night is one line that opens to its groups.
    private func folded(_ dream: Dream) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showsNight.toggle() }
            } label: {
                HStack(spacing: 8) {
                    SkyGlyph(sky: .moon, side: 20)
                    Text(isToday(dream) ? "Last night" : "Your last dream")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariSecondary)
                    Text("· \(dreamt(dream).replacingOccurrences(of: "Dreamt at ", with: ""))")
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Chevron(isOpen: showsNight)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsNight ? "Shown" : "Folded")
            if showsNight {
                groups(dream).transition(.opacity)
            }
            hairline.padding(.top, 6)
        }
    }

    static func title(_ group: DreamGroup) -> String {
        switch group {
        case .planned: "Planned"
        case .tidied: "Tidied"
        case .saved: "Saved for you"
        default: "Noticed"
        }
    }

    // MARK: Plans

    private var groups: PlanGroups {
        PlanReading.group(session.desk?.plans ?? [], now: DeskClock.now())
    }

    private var plans: some View {
        let groups = groups
        return VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel("Plans today")
            if groups.today.isEmpty {
                Text("Nothing more planned today.")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            ForEach(groups.today) { plan in
                PlanLine(plan: plan) { detail = .plan(plan) }
            }
            if groups.beyondToday > 0 {
                MoreLink(
                    text:
                        "\(groups.allThisWeek ? "Later this week" : "Later") · \(groups.beyondToday) more"
                ) { path.append(.plans) }
            } else if !groups.today.isEmpty {
                MoreLink(text: "All plans") { path.append(.plans) }
            }
        }
    }

    // MARK: Done

    /// What Kumo did today, leaving out the dream's own changes, which show with the dream.
    private var handled: [DoneEntry] {
        (work?.handled ?? []).filter { $0.dream == nil }
    }

    private static let shown = 3

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskSectionLabel("Done today")
            if let work {
                if handled.isEmpty {
                    Text("Nothing yet today.").font(.footnote).foregroundStyle(.ariTertiary)
                }
                ForEach(handled.prefix(Self.shown)) { entry in
                    DoneLine(entry: entry) { detail = .done(entry) }
                }
                let more = max(0, handled.count - Self.shown) + work.cleared.count
                MoreLink(text: more > 0 ? "and \(more) more" : "Everything I've done") {
                    path.append(.allWork)
                }
            } else if let workProblem {
                DeskProblemLine(text: workProblem)
                DeskPill(title: "Try again") { Task { await load() } }
            } else {
                ProgressView().tint(.ariSecondary)
            }
        }
    }

    private func load() async {
        do {
            work = try await session.work()
            workProblem = nil
        } catch {
            workProblem = "Couldn't load today's work: \(DeskSending.words(for: error))"
        }
    }

    private func undo(_ entry: DoneEntry) async throws -> DoneEntry {
        let undone = try await session.undo(entry.id)
        await load()
        return undone
    }

    private func correct(_ entry: DoneEntry, _ words: String?) async throws -> DoneEntry {
        let corrected = try await session.correct(entry.id, text: words)
        await load()
        return corrected
    }

    // MARK: Dream now

    /// At the foot, beside when Kumo dreams: Dream now, or, while it dreams, a way to watch. A
    /// server that can't dream shows none of it.
    @ViewBuilder
    private var dreamNow: some View {
        if let dreams, let state = dreams.state {
            VStack(alignment: .leading, spacing: 10) {
                if dreams.dreaming != nil {
                    HStack(spacing: 14) {
                        DeskPill(title: "Dreaming…") {}.disabled(true)
                        MoreLink(text: "Watch") { watching = true }
                    }
                } else {
                    DeskPill(title: "Dream now", busy: dreams.asking) {
                        Task {
                            dreamProblem = nil
                            do {
                                try await dreams.dreamNow()
                            } catch {
                                dreamProblem =
                                    "Couldn't start dreaming: \(DeskSending.words(for: error))"
                            }
                        }
                    }
                    .disabled(dreams.asking)
                    .waitsForConnection()
                }
                if let dreamProblem { DeskProblemLine(text: dreamProblem) }
                Text(foot(state))
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    /// "I dream at 04:00 each night. Change the time in Settings.", after a dream you asked for
    /// today with when the next one is.
    private func foot(_ state: DreamState) -> String {
        if let dream, dream.trigger == .manual, isToday(dream) {
            let at = dream.startedAt.date.formatted(DeskTime.time)
            let next = state.nextAt.date
            let tonight = Calendar.current.isDate(
                next,
                inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: DeskClock.now())
                    ?? next)
            return
                "Dreamt at \(at). I'll still dream at \(state.time) \(tonight ? "tonight" : "after that"). Change the time in Settings."
        }
        return "I dream at \(state.time) each night. Change the time in Settings."
    }
}

// MARK: - Lines

/// A line from the dream: what Kumo did, plainly; a tap opens why, and Undo.
struct DreamLineRow: View {
    let line: DreamLine
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.text)
                    .font(.subheadline)
                    .foregroundStyle(line.undone ? Color.ariTertiary : .ariText)
                    .strikethrough(line.undone, color: .ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.ariTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(line.undone ? "Taken back" : "")
        .accessibilityHint("Shows why, and Undo")
    }
}

/// One of Kumo's plans as a line: its time, its plain title, and how it repeats.
struct PlanLine: View {
    let plan: WakeUp
    /// "Thu 12:00" rather than "12:00", for plans on other days.
    var showsDay = false
    let open: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 46

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(time)
                    .monospacedDigit()
                    .foregroundStyle(.ariTertiary)
                    .frame(minWidth: showsDay ? timeWidth * 1.6 : timeWidth, alignment: .leading)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.shownTitle)
                        .foregroundStyle(.ariText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let repeating = plan.repeat {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.caption2.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(PlanWords.ending(PlanWords.repeats(repeating), repeating))
                        }
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                }
                Spacer(minLength: 8)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows why, and what \(LeadName.current) will do")
    }

    private var time: String {
        let time = plan.at.date.formatted(DeskTime.time)
        guard showsDay else { return time }
        return "\(plan.at.date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// Something Kumo did, as a line: a tick, what, and when; a tap opens why, with Undo.
struct DoneLine: View {
    let entry: DoneEntry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: entry.isCorrected ? "arrow.uturn.backward" : "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariSecondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(entry.text)
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(entry.at.date, format: DeskTime.time)
                    .monospacedDigit()
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows why, with Undo and That was wrong")
    }
}

/// A quiet link to more: "Later this week · 6 more ›".
struct MoreLink: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.footnote)
            .foregroundStyle(.ariTertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
