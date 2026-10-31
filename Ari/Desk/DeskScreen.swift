import AriKit
import SwiftUI

/// Where Ito opens, and home for everything admin: Kumo, the morning card, what's coming up, what's
/// waiting on you, and Tell Kumo. It rolls and never resets: each part keeps its own clock. Talking
/// lives in the chat; a quick word told here goes there, and Kumo's reply shows here too.
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
    @State private var briefingFolded = false
    /// The morning card you've already seen: it folds to one line from then on.
    @AppStorage("readBriefing") private var readBriefing = ""
    @State private var openedItem: CalendarItem?
    @State private var openedCard: DeskCard?
    @State private var showsDone = false
    @State private var presence = PoseHistory()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let briefing = session.desk?.briefing {
                    BriefingCard(
                        briefing: briefing, folded: $briefingFolded,
                        open: open(_:), openHandled: { showsDone = true }
                    )
                    .task(id: briefing.id) { await seen(briefing) }
                }
                if let items = session.desk?.comingUp, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        DeskSectionLabel("Coming up")
                        ComingUpList(items: items, symbol: symbol(for:)) { openedItem = $0 }
                    }
                }
                if let cards = session.desk?.waiting, !cards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        DeskSectionLabel("Waiting on you", trailing: "\(cards.count)")
                        WaitingList(cards: cards, context: context(for:)) {
                            openedCard = $0
                        } answer: {
                            card, answer in
                            try await session.answer(card.id, answer)
                        }
                    }
                }
                if let desk = session.desk, desk.briefing == nil, desk.comingUp.isEmpty,
                    desk.waiting.isEmpty
                {
                    Text("Nothing needs you.")
                        .font(.ariBody)
                        .foregroundStyle(.ariSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(.ariBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .sheet(item: $openedItem) { CalendarEventView(item: $0) }
        .sheet(item: $openedCard) { card in
            NavigationStack {
                ScrollView {
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
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showsDone) {
            NavigationStack { AllDoneView(session: session) }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                PresenceView(history: presence, size: 38)
                    .padding(.bottom, 4)
                Text(LeadName.current).font(.ariName).foregroundStyle(.ariText)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            .frame(maxWidth: .infinity)
            SettingsButton(action: openSettings)
        }
        .padding(.top, 12)
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

    private func open(_ line: BriefingLine) {
        guard let card = line.card else { return }
        openedCard = session.desk?.waiting.first { $0.id == card }
    }

    /// A morning card you've seen before comes folded; one on screen for a few seconds counts as
    /// read, which lets the box make a "since this morning" one later.
    private func seen(_ briefing: Briefing) async {
        briefingFolded = readBriefing == briefing.id.rawValue || briefing.readAt != nil
        guard !briefingFolded else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        readBriefing = briefing.id.rawValue
        try? await session.readBriefing(briefing.id)
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

/// Everything Kumo did: "Also handled 9 small things" opens it.
private struct AllDoneView: View {
    let session: Session

    @State private var entries: [DoneEntry] = []
    @State private var hasMore = true

    var body: some View {
        DoneView(
            entries: entries, hasMore: hasMore,
            undo: { _ = try await session.undo($0.id) },
            correct: { entry, words in _ = session.send(words, done: entry.id) },
            loadMore: load)
    }

    private func load() async throws {
        let page = try await session.done(before: entries.last?.id)
        entries += page.entries
        hasMore = page.hasMore
    }
}
