import AriKit
import SwiftUI

/// Where Ito opens, and home for everything admin: Kumo's line for the moment, what's coming up,
/// what's waiting on you, Done, and Tell Kumo. It rolls and never resets: each part
/// keeps its own clock. Talking lives in the chat; a quick word told here goes there, and Kumo's
/// reply shows here too.
struct DeskScreen: View {
    let session: Session
    let openChat: () -> Void
    let openSettings: () -> Void
    /// Starts a call, which happens in the chat.
    var talk: (() -> Void)?
    var talkReady = true

    @State private var draft = ""
    /// The message you last told Kumo here, for the card that shows Kumo's reply.
    @State private var told: MessageID?
    @State private var openedItem: CalendarItem?
    @State private var openedCard: DeskCard?
    @State private var showsWork = false
    /// A day of Kumo's calls to glance at, from a review card's first option.
    @State private var glancing: ReviewCard?
    /// Your answer to Kumo's line on its way.
    @State private var sending = DeskSending()
    /// What followed an answer Kumo has just acted on, from Done, for a minute after its card left.
    @State private var followed: DoneEntry?
    /// What's wrong on the server, opened from "Something's wrong ›" to see how to fix it.
    @State private var showsProblems = false
    /// When you last left the Desk; cards that changed after it carry a dot while you're here.
    @AppStorage("deskLookedAt") private var lookedAt = 0.0
    @State private var lastLook = Date.now
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                KumoSays(
                    moment: kumoMoment, liveness: liveness,
                    openWork: { showsWork = true }, openSettings: openSettings,
                    openProblems: { showsProblems = true }, answer: answerMoment(_:),
                    skip: skipMoment, sending: sending
                )
                .task(id: unread) { await read() }
                if let items = session.desk?.comingUp, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        DeskSectionLabel("Coming up")
                        ComingUpList(
                            items: items, symbol: symbol(for:), open: { openedItem = $0 },
                            guess: { $0.guess?.why },
                            answerGuess: { item, answer in
                                try await session.answerGuess(item.id, answer)
                            },
                            unfoldedGuess: shownGuess(items, "open"),
                            correctingGuess: shownGuess(items, "correct"))
                    }
                }
                if let cards = session.desk?.waiting, !cards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        DeskSectionLabel("Waiting on you", trailing: "\(cards.count)")
                        WaitingList(
                            cards: cards, context: context(for:), open: { openedCard = $0 },
                            answer: { card, given in try await answer(card, given) },
                            changed: changed(cards))
                    }
                }
                if let followed {
                    FollowedLine(entry: followed) { showsWork = true }
                        .task(id: followed.id) {
                            try? await Task.sleep(for: .seconds(60))
                            if !Task.isCancelled { self.followed = nil }
                        }
                }
                if session.desk != nil {
                    DeskDoneLine { showsWork = true }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .sheet(isPresented: isGlancing) {
                NavigationStack { KumosWorkScreen(session: session, review: glancing) }
                    .presentationDetents([.large])
            }
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .sheet(item: $openedItem) { CalendarEventView(item: $0) }
        .sheet(item: $openedCard) { opened in
            // As the Desk has it now, such as redrafting, rather than as it was when opened.
            let card = session.desk?.waiting.first { $0.id == opened.id } ?? opened
            NavigationStack {
                ScrollView {
                    DeskCardView(card: card, context: context(for: card)) { given in
                        try await answer(card, given)
                        openedCard = nil
                    }
                    .padding(16)
                }
                .background(.ariBackground)
                .navigationTitle(CardLook.name(card.kind))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showsWork) {
            NavigationStack { kumosWork }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsProblems) { ProblemsSheet(problems: session.problems) }
        // Once the server has nothing wrong, there's nothing left to fix.
        .onChange(of: session.problems.isEmpty) { _, fixed in
            if fixed { showsProblems = false }
        }
        .onChange(of: working) { before, now in
            let settled = before.filter { now[$0.key] == nil }.map(\.value)
            if !settled.isEmpty { Task { await showFollowed(settled) } }
        }
        .onAppear { startLook() }
        #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1))
                if DebugScript.opensKumosWork { showsWork = true }
            }
        #endif
        .onDisappear { endLook() }
        // Only leaving for the background ends a visit: Control Center, a notification pulled down
        // or the way back from the background pass through inactive, and ending the visit there
        // cleared the dots of what changed while you were away.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: startLook()
            case .background: endLook()
            default: break
            }
        }
        // A failed answer belongs to its line: Kumo's next line starts without it.
        .onChange(of: session.desk?.moment?.id) { _, _ in sending.clearProblem() }
        .animation(.smooth(duration: 0.35), value: followed)
        .animation(.smooth(duration: 0.35), value: session.problems)
    }

    /// Kumo's work, opened from its face or Done.
    private var kumosWork: some View {
        #if DEBUG
            KumosWorkScreen(
                session: session, opensAtTrust: DebugScript.kumosWork == "trust",
                asksWrongAtFirst: DebugScript.kumosWork == "wrong")
        #else
            KumosWorkScreen(session: session)
        #endif
    }

    private var isGlancing: Binding<Bool> {
        Binding(get: { glancing != nil }, set: { if !$0 { glancing = nil } })
    }

    /// Answers a card; a review card's first option goes on to open the day's calls to glance at.
    private func answer(_ card: DeskCard, _ answer: CardAnswer) async throws {
        try await session.answer(card.id, answer)
        if card.glances(answer) { glancing = card.review }
    }

    /// Kumo's line from the box, or all quiet in the app's own words.
    private var kumoMoment: KumoMoment? {
        guard let desk = session.desk else { return nil }
        guard let moment = desk.moment else {
            return .quiet(handled: desk.handled, waiting: !desk.waiting.isEmpty)
        }
        return KumoMoment(moment)
    }

    private var liveness: KumoLiveness {
        KumoLiveness(lastMail: session.desk?.lastMailAt, hasProblems: !session.problems.isEmpty)
    }

    /// Kumo's line while nobody has said it was read, and Ito is in front.
    private var unread: MomentID? {
        guard scenePhase == .active, let moment = session.desk?.moment, moment.readAt == nil
        else { return nil }
        return moment.id
    }

    /// Kumo's line on screen for a moment counts as read, in the chat too, so no notification
    /// goes out for it. Saying so tries again until it goes through, while the line is still on
    /// screen and unread: a lost request would otherwise let the notification out for a line
    /// you've seen.
    private func read() async {
        guard let unread else { return }
        try? await Task.sleep(for: .seconds(1.5))
        var wait = Duration.seconds(2)
        while !Task.isCancelled {
            do throws(RequestError) {
                try await session.readMoment(unread)
                return
            } catch {
                // Only a lost request or a busy server is worth asking again.
                guard error.isTemporary else { return }
            }
            try? await Task.sleep(for: wait)
            wait = min(wait * 2, .seconds(60))
        }
    }

    /// Answers Kumo's line, with one of its replies or your words, as a card's answer goes.
    private func answerMoment(_ answer: CardAnswer) async throws {
        guard let moment = session.desk?.moment else { return }
        try await session.answerMoment(moment.id, answer)
    }

    /// The first guess, shown open or with its choices from `ARI_GUESS`, in debug builds.
    private func shownGuess(_ items: [CalendarItem], _ wanted: String) -> CalendarItemID? {
        #if DEBUG
            guard DebugScript.guess == wanted else { return nil }
            return items.first { $0.guess != nil }?.id
        #else
            return nil
        #endif
    }

    /// Skip, on the day's question: it goes at once, and Kumo never asks it again.
    private func skipMoment() async throws {
        guard let moment = session.desk?.moment else { return }
        try await session.skipMoment(moment.id)
    }

    /// The cards that are new or changed since you last left the Desk.
    private func changed(_ cards: [DeskCard]) -> Set<CardID> {
        Set(cards.filter { ($0.changedAt ?? $0.at).date > lastLook }.map(\.id))
    }

    /// A visit begins: the dots compare with the end of the last one, or none on the first.
    private func startLook() {
        lastLook = lookedAt > 0 ? Date(timeIntervalSince1970: lookedAt) : .now
    }

    private func endLook() {
        lookedAt = Date.now.timeIntervalSince1970
    }

    /// The cards the box is acting on, by id, with their titles.
    private var working: [CardID: String] {
        Dictionary(
            (session.desk?.waiting ?? []).filter(\.isWorking).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first })
    }

    /// Once a card you answered has left, what Done says came of it: your answer, and Kumo's line.
    private func showFollowed(_ titles: [String]) async {
        guard let page = try? await session.done() else { return }
        if let entry = page.entries.first(where: { entry in
            titles.contains { entry.text.contains("“\($0)”") }
        }) {
            followed = entry
        }
    }

    /// Tell Kumo, and above it, the last thing you told it with Kumo's reply as it comes.
    private var bottom: some View {
        VStack(spacing: 0) {
            if let told {
                ReplyCard(session: session, message: told, openChat: openChat) { self.told = nil }
            }
            Composer(
                draft: $draft,
                role: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .send,
                prompt: "Tell \(LeadName.current)…",
                send: send, stop: {}, talk: talk, talkReady: talkReady)
        }
        .background(.ariBackground)
    }

    private func send() {
        guard let id = session.send(draft) else { return }
        told = id
        draft = ""
    }

    /// The card's corner: the thing in motion it's about, such as "Job search".
    private func context(for card: DeskCard) -> String? {
        guard let motion = card.motion else { return nil }
        return session.motions?.all.first { $0.id == motion }?.title
    }

    private func symbol(for item: CalendarItem) -> String? {
        item.allDay && item.motion != nil ? "airplane" : nil
    }
}

/// Something you told Kumo on the Desk, with Kumo's reply streaming in under it: a few lines at most,
/// with the whole conversation one tap away.
private struct ReplyCard: View {
    let session: Session
    let message: MessageID
    let openChat: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let (said, reply) = exchange
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("You: \(said)")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.ariTertiary)
                .accessibilityLabel("Close")
            }
            Text(reply.isEmpty ? "…" : reply)
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                openChat()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Text("Open in Chat")
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ariBone)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ariSurface))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                .ariLine.opacity(0.7))
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// What you said, and Kumo's reply to it so far: its shown replies after your message, joined.
    private var exchange: (said: String, reply: String) {
        let entries = session.conversation.entries
        guard let index = entries.firstIndex(where: { $0.id == message }) else { return ("", "") }
        let reply = entries[(index + 1)...]
            .filter { $0.role == .agent && $0.isShown }
            .map(\.text)
            .joined(separator: "\n\n")
        return (entries[index].text, reply)
    }
}

/// What came of an answer you gave on the Desk, in one quiet line: what you answered, and Kumo's
/// line on what followed. A tap opens everything Kumo did.
private struct FollowedLine: View {
    let entry: DoneEntry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ariBone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.subheadline)
                        .foregroundStyle(.ariText)
                    if let reason = entry.reason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.ariSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows everything \(LeadName.current) did")
        .transition(.opacity)
    }
}
