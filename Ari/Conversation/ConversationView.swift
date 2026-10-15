import AriKit
import SwiftUI

/// The conversation: the floating header, everything said so far, and the composer. All of it
/// comes from the session; this view adds only what's about the screen: the reading pace, the
/// character's poses, holding each status long enough to read, and where you've scrolled.
struct ConversationView: View {
    let session: Session
    var name = "Ari"
    let connectAgain: () -> Void

    @State private var reveal = Reveal()
    @State private var poses = PoseHistory()
    @State private var draft = ""
    @State private var sheet: SheetItem?
    /// The trail's runs and steps you've opened.
    @State private var opened: Set<String> = []
    // Scrolled by message, not by edge: scrolling to an edge also shifts the content sideways.
    @State private var position = ScrollPosition(idType: String.self)
    @State private var distanceFromEnd: CGFloat = 0
    /// Whether the conversation follows what arrives. It does while you're at the end, stops once
    /// you scroll up, and starts again when you come back to the end, send, or tap the pill.
    @State private var following = true
    @State private var repliedWhileAway = false
    @State private var status: StatusText?
    @State private var statusSince = Date.distantPast
    @State private var linkDown = false
    @State private var stopped = false

    var body: some View {
        let conversation = session.conversation
        let revealing = reveal.isRevealing(conversation)
        let working = conversation.turn != nil || revealing
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Rhythm.messageGap) {
                    if conversation.entries.isEmpty {
                        Text("Nothing here yet. Say hello.")
                            .font(.ariBody)
                            .foregroundStyle(.ariTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                    }
                    ForEach(rows(conversation)) { row in
                        rowView(row, in: conversation)
                            .id(row.id)
                            .onAppear {
                                if row.id == rows(conversation).first?.id { loadEarlier() }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
                // A comfortable reading width on a wide Mac window.
                .frame(maxWidth: Rhythm.column)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            // Drag the conversation down and the keyboard follows your finger away.
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($position)
            // Anchored at the leading edge: a centred anchor can shift everything sideways when
            // the composer grows or the keyboard moves.
            .defaultScrollAnchor(.bottomLeading)
            // Following, the end stays in view as the reply grows; scrolled up, your place stays.
            .defaultScrollAnchor(following ? .bottomLeading : .topLeading, for: .sizeChanges)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
            } action: { _, distance in
                distanceFromEnd = distance
            }
            // The anchor can slip while a row's height is still an estimate, so whenever the
            // conversation grows while following, it also settles at the new end.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { old, new in
                if following, new > old { scrollToEnd() }
            }
            // Scrolling yourself stops the following; coming to rest at the end starts it again.
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking, .interacting: following = false
                case .idle where distanceFromEnd < 40:
                    following = true
                    repliedWhileAway = false
                default: break
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HeaderView(poses: poses, name: name, status: status)
            }
            .overlay(alignment: .bottom) {
                if let pill = pillText(working: working) {
                    Pill(text: pill) { scrollToEnd() }
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: pillText(working: working))

            if let problem = session.problem {
                ProblemNotice(problem: problem, connectAgain: connectAgain)
            } else {
                // While Ari waits for your answer, the composer takes it, as a secret if asked.
                let asking = revealing ? nil : conversation.waitingAsk
                Composer(
                    draft: $draft, role: role(working: working, asking: asking != nil),
                    prompt: asking.map(Self.takesTypedAnswer) == true
                        ? "Answer Ari" : "Message Ari",
                    secret: asking?.secret ?? false, send: send, stop: stop
                )
                .frame(maxWidth: Rhythm.column)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.ariBackground)
        .background {
            // The reading pace moves on with each frame, only while something is being revealed.
            TimelineView(.animation(paused: !revealing)) { context in
                Color.clear.onChange(of: context.date) { previous, now in
                    reveal.advance(
                        by: min(now.timeIntervalSince(previous), 0.1), in: session.conversation)
                }
            }
        }
        .onChange(of: pose(revealing: revealing), initial: true) { _, pose in poses.set(pose) }
        .onChange(of: liveStatus(revealing: revealing), initial: true) { _, next in hold(next) }
        .onChange(of: session.link, initial: true) { _, link in noticeLink(link) }
        .onChange(of: conversation.lastEndedTurn?.id) { _, _ in noticeEnd(conversation) }
        .onChange(of: working) { wasWorking, isWorking in
            if wasWorking, !isWorking, !following { repliedWhileAway = true }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .details(let error): DetailsSheet(error: error)
            case .selecting(let text): SelectTextSheet(text: text)
            }
        }
        #if DEBUG
            .task {
                if let draft = DebugScript.draft { self.draft = draft }
                await DebugScript.run(in: session, stop: stop)
            }
        #endif
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        enum Kind {
            case day(Date)
            case yours(Conversation.Entry)
            case ari(Conversation.Entry)
            case trail(Trail)
            /// A turn that failed before writing anything.
            case failure(TurnID, ServerError?)
        }

        let id: String
        let kind: Kind
    }

    /// The conversation as it reads (messages, and Ari's trail between them), with the date at the
    /// start of each day.
    private func rows(_ conversation: Conversation) -> [Row] {
        var rows: [Row] = []
        var day: Date?
        for item in Timeline(conversation, reveal: reveal).items {
            guard case .message(let entry) = item else {
                if case .trail(let trail) = item {
                    rows.append(Row(id: trail.id, kind: .trail(trail)))
                }
                continue
            }
            let date = entry.at?.date ?? .now
            if day.map({ !Calendar.current.isDate($0, inSameDayAs: date) }) ?? true {
                rows.append(Row(id: "day \(entry.id)", kind: .day(date)))
                day = date
            }
            rows.append(
                Row(id: entry.id.rawValue, kind: entry.role == .user ? .yours(entry) : .ari(entry)))
        }
        if let ended = conversation.lastEndedTurn, ended.outcome == .failed,
            !conversation.entries.contains(where: {
                $0.turn == ended.id && $0.isShown && $0.role == .agent
            })
        {
            rows.append(Row(id: "failure \(ended.id)", kind: .failure(ended.id, ended.error)))
        }
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row, in conversation: Conversation) -> some View {
        switch row.kind {
        case .day(let date):
            DayLabel(date: date)
        case .yours(let entry):
            YourMessage(
                text: entry.isSecret ? "••••••" : entry.text, tag: tag(for: entry, in: conversation)
            )
        case .ari(let entry):
            let text = conversation.visibleText(of: entry)
            let shown = reveal.position(of: entry)
            let position = shown >= Double(text.utf16.count) ? .infinity : shown
            VStack(alignment: .leading, spacing: 8) {
                if !text.isEmpty {
                    ReplyView(document: ReplyDocument(markdown: text), position: position)
                }
                if position == .infinity { footer(for: entry, in: conversation) }
            }
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(entry.text) }
                Button("Select Text", systemImage: "selection.pin.in.out") {
                    sheet = .selecting(entry.text)
                }
                ShareLink(item: entry.text)
            } preview: {
                // A long reply lifted whole would cover the screen, so the menu shows its opening.
                ReplyPreview(text: entry.text)
            }
        case .trail(let trail):
            TrailView(
                trail: trail, conversation: conversation, reveal: reveal, opened: $opened,
                answer: answer)
        case .failure(let turn, let error):
            failureLine(turn: turn, error: error, in: conversation)
        }
    }

    /// Under your message: whether the server has it, and whether Ari took it in or it waits.
    private func tag(for entry: Conversation.Entry, in conversation: Conversation) -> String? {
        if session.refusedMessages[entry.id] != nil { return "Couldn't send" }
        if entry.delivery == .sending {
            return session.link == .live ? "Sending" : "Waiting to send"
        }
        if entry.isSecret { return "Hidden from your history" }
        switch entry.mark {
        case .next: return "Next"
        case .read:
            // Once the adjusted reply starts, the reply itself shows Ari listened.
            let index = conversation.entries.firstIndex { $0.id == entry.id } ?? 0
            let answered = conversation.entries[index...].contains {
                $0.role == .agent && $0.isShown
            }
            return answered ? nil : "Read"
        default: return nil
        }
    }

    /// Under a reply, once it's all on screen: how it ended, if not as it should.
    @ViewBuilder
    private func footer(for entry: Conversation.Entry, in conversation: Conversation) -> some View {
        switch entry.outcome {
        case .stopped: Tag(text: "Stopped")
        case .interrupted: Tag(text: "Interrupted · Your server restarted")
        case .failed:
            if let turn = entry.turn {
                failureLine(turn: turn, error: entry.error, in: conversation)
            }
        default: EmptyView()
        }
    }

    private func failureLine(turn: TurnID, error: ServerError?, in conversation: Conversation)
        -> some View
    {
        FailureLine(
            message: "Couldn't finish. "
                + (error?.message ?? "Something went wrong on the server."),
            canTryAgain: !conversation.retriedTurns.contains(turn),
            tryAgain: { session.tryAgain(turn) },
            details: {
                sheet = .details(
                    error
                        ?? ServerError(code: ErrorCode(rawValue: "unknown"), message: "No details.")
                )
            })
    }

    // MARK: - What you do

    private func role(working: Bool, asking: Bool) -> Composer.Role {
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .send }
        if working, session.conversation.pendingStop == nil { return .stop }
        // Stop while Ari waits for you cancels what it asked.
        return asking ? .stop : .idle
    }

    /// Whatever you send while Ari waits answers it. A secret names the ask, and keeps no text.
    private func send() {
        let asking = session.conversation.waitingAsk
        let secret = asking?.secret ?? false
        guard session.send(draft, answers: secret ? asking?.id : nil, secret: secret) != nil
        else { return }
        draft = ""
        scrollToEnd()
    }

    /// Whether an ask takes a typed answer. Any message still answers it, but the composer only
    /// invites one when the ask does.
    private static func takesTypedAnswer(_ ask: Ask) -> Bool {
        ask.allowsText || ask.options.isEmpty || ask.secret
    }

    /// You tapped one of an ask's options: its label is your answer.
    private func answer(_ ask: Ask, _ option: Ask.Option) {
        guard session.send(option.label, answers: ask.id) != nil else { return }
        scrollToEnd()
    }

    private func scrollToEnd() {
        guard let last = rows(session.conversation).last?.id else { return }
        following = true
        repliedWhileAway = false
        withAnimation(.smooth(duration: 0.4)) {
            position.scrollTo(id: last, anchor: .bottomLeading)
        }
    }

    /// Stop names the message the server is still writing, at how much of it is on screen.
    private func stop() {
        let conversation = session.conversation
        if conversation.turn == nil, !reveal.isRevealing(conversation),
            let ask = conversation.waitingAsk
        {
            session.cancel(ask.id)
            return
        }
        session.stop(cut: reveal.stop(in: conversation))
    }

    private func loadEarlier() {
        guard session.conversation.hasEarlierMessages, !session.isLoadingEarlier else { return }
        Task { await session.loadEarlier() }
    }

    // MARK: - Status and poses

    private func pose(revealing: Bool) -> Pose {
        if linkDown { return .offline }
        if let turn = session.conversation.turn {
            if session.conversation.pendingStop != nil { return .stopping }
            return turn.status.map { Pose(kind: $0.kind) } ?? .thinking
        }
        if revealing { return .writing }
        return session.conversation.waitingAsk == nil ? .resting : .asking
    }

    private func liveStatus(revealing: Bool) -> StatusText? {
        if linkDown { return .quiet(session.link == .offline ? "No connection" : "Reconnecting") }
        let conversation = session.conversation
        if let turn = conversation.turn {
            if conversation.pendingStop != nil { return .status("Stopping", detail: nil) }
            return turn.status.map { .status($0.label, detail: $0.detail) }
        }
        if revealing { return .status("Writing", detail: nil) }
        if conversation.waitingAsk != nil { return .status("Waiting for you", detail: nil) }
        return stopped ? .quiet("Stopped") : nil
    }

    /// Each status stays at least a second, so it can be read; a newer one waits its turn, and
    /// any it replaces meanwhile are skipped. A status never outlives its turn, though: when there's
    /// nothing to say, the line clears at once.
    private func hold(_ next: StatusText?) {
        let wait = 1 - Date.now.timeIntervalSince(statusSince)
        guard wait > 0, status != nil, next != nil else {
            status = next
            statusSince = .now
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            let latest = liveStatus(revealing: reveal.isRevealing(session.conversation))
            if latest != status {
                status = latest
                statusSince = .now
            }
        }
    }

    /// A connection lost for two seconds shows; a shorter blip never does.
    private func noticeLink(_ link: Session.Link) {
        guard link == .reconnecting || link == .offline else {
            linkDown = false
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if session.link == .reconnecting || session.link == .offline { linkDown = true }
        }
    }

    private func noticeEnd(_ conversation: Conversation) {
        guard conversation.lastEndedTurn?.outcome == .stopped else { return }
        stopped = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            stopped = false
        }
    }

    private func pillText(working: Bool) -> String? {
        guard !following, distanceFromEnd >= 40 else { return nil }
        if working { return "Ari is writing" }
        if repliedWhileAway { return "Ari has replied" }
        return distanceFromEnd > 600 ? "Latest" : nil
    }
}

/// What needs you before Ari can carry on, in place of the composer.
private struct ProblemNotice: View {
    let problem: Session.Problem
    let connectAgain: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch problem {
            case .tokenRejected(let error):
                Text(error?.message ?? "Your server no longer accepts this token.")
                    .foregroundStyle(.ariSecondary)
                Button("Connect again", action: connectAgain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ariText)
            case .protocolMismatch(let mismatch):
                Text(
                    mismatch.update == .ari
                        ? "Your server now speaks a newer protocol. Update Ari."
                        : "Your server speaks an older protocol. Update Ito on your server."
                )
                .foregroundStyle(.ariSecondary)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
