import AriKit
import SwiftUI

/// The conversation: the floating header, everything said so far, and the composer. All of it
/// comes from the session; this view adds only what's about the screen: the reading pace, the
/// character's poses, holding each status long enough to read, and where you've scrolled.
struct ConversationView: View {
    let session: Session
    var name = "Ari"
    let connectAgain: () -> Void
    /// A reply to open the conversation at, from a tapped notification.
    var opening: Binding<MessageID?> = .constant(nil)
    /// Whether Ari may offer notifications, once a turn takes a while.
    var offersNotifications = false
    var answerOffer: (Bool) -> Void = { _ in }

    @State private var reveal = RevealModel()
    @State private var poses = PoseHistory()
    /// Photos and files on the message you're writing, uploading as you write.
    @State private var attached: [PendingAttachment] = []
    /// Something you picked that can't be attached, said for a few seconds.
    @State private var attachProblem: String?
    @State private var sheet: SheetItem?
    /// The trail's runs and steps you've opened.
    @State private var opened: Set<String> = []
    // Scrolled by message, not by edge: scrolling to an edge also shifts the content sideways.
    @State private var position = ScrollPosition(idType: String.self)
    @State private var distanceFromEnd = Distance.atEnd
    /// Whether your finger is on the conversation.
    @State private var scrolling = false
    /// The first row on screen, once you've scrolled back past the latest ones; `nil` shows the
    /// latest.
    @State private var firstShown: String?
    /// Whether the conversation follows what arrives. It does while you're at the end, stops once
    /// you scroll up, and starts again when you come back to the end, send, or tap the pill.
    @State private var following = true
    @State private var repliedWhileAway = false
    @State private var status: StatusText?
    @State private var statusSince = Date.distantPast
    @State private var poseSince = Date.distantPast
    @State private var linkDown = false
    @State private var stopped = false
    /// A turn has run long enough that a nudge when it's done would help.
    @State private var offering = false
    /// A linked page, open in place.
    @State private var browsing: WebPage?
    /// Rows and parsed replies, kept between frames: a reply revealing redraws the screen every
    /// frame, and working the whole conversation out again each time froze long ones.
    @State private var cache = RowsCache()
    /// Each send and each Stop, for a light tap you can feel.
    @State private var sent = 0
    @State private var stops = 0

    var body: some View {
        let conversation = session.conversation
        let working = conversation.turn != nil || reveal.isRevealing
        // Stop while Ari works, or while it waits for you, which cancels what it asked.
        let canStop =
            (working && conversation.pendingStop == nil)
            || (!working && conversation.waitingAsk != nil)
        let target = conversation.turn?.id.rawValue ?? conversation.waitingAsk?.id.rawValue ?? ""
        let stopCommand = canStop ? StopCommand(target: target, perform: { stop() }) : nil
        screen
            // Files dropped on the conversation attach to the message you're writing.
            .dropDestination(for: URL.self) { urls, _ in drop(urls) }
            .sensoryFeedback(.impact(weight: .light), trigger: sent)
            .sensoryFeedback(.impact(weight: .medium), trigger: stops)
            .focusedSceneValue(\.stop, stopCommand)
            #if os(iOS)
                // Links in replies open in place, over the conversation.
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        guard WebPage.opens(url) else { return .systemAction }
                        browsing = WebPage(url: url)
                        return .handled
                    }
                )
                .sheet(item: $browsing) { page in
                    BrowserView(page: page).ignoresSafeArea()
                }
            #endif
            .sheet(item: $sheet) { item in
                switch item {
                case .details(let error): DetailsSheet(error: error)
                case .selecting(let text): SelectTextSheet(text: text)
                }
            }
            #if DEBUG
                .task {
                    for url in DebugScript.attachments {
                        if let attachment = try? await AttachmentMaker.file(at: url) {
                            attach(attachment)
                        }
                    }
                    await DebugScript.run(
                        in: session,
                        send: { message in _ = send(message) }, stop: stop)
                }
            #endif
    }

    /// The conversation itself, the composer, and what follows the session and the screen.
    private var screen: some View {
        let conversation = session.conversation
        let revealing = reveal.isRevealing
        let working = conversation.turn != nil || revealing
        let rows = rows(conversation)
        let shown = shownRows(rows)
        return ScrollView {
            // A plain stack of the latest rows, not a lazy one: a lazy stack guesses the heights of
            // rows it hasn't drawn, and when the guesses were wrong the conversation jumped, or
            // scrolled past its end into blank space.
            VStack(spacing: Rhythm.messageGap) {
                if conversation.entries.isEmpty {
                    Text("Nothing here yet. Say hello.")
                        .font(.ariBody)
                        .foregroundStyle(.ariTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
                ForEach(shown) { row in
                    rowView(row, in: conversation)
                        // A comfortable reading width on a wide Mac window, inside a row as wide as
                        // the screen: scrolling to a row lines up its edge with the screen's, so a
                        // row starting at its margin slid the whole conversation sideways.
                        .frame(maxWidth: Rhythm.column, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .id(row.id)
                        .onAppear {
                            if row.id == shown.first?.id { showEarlier(rows) }
                        }
                }
                // The end, exactly: what following and the pill scroll to.
                Color.clear.frame(maxWidth: .infinity).frame(height: 1).id(Self.end)
            }
            .scrollTargetLayout()
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        // Drag the conversation down and the keyboard follows your finger away.
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        // Following, the end stays in view as the reply grows; scrolled up, your place stays.
        .defaultScrollAnchor(following ? .bottom : .top, for: .sizeChanges)
        // Only how far from the end, roughly: a value that changed on every scrolled point
        // redrew the whole conversation each time.
        .onScrollGeometryChange(for: Distance.self) { geometry in
            Distance(geometry.contentSize.height - geometry.visibleRect.maxY)
        } action: { _, distance in
            distanceFromEnd = distance
            // Back at the end without a finger on the screen, as a fling comes to rest: follow.
            if distance == .atEnd, !scrolling { follow() }
        }
        // A new row while following: settle at the end, at once. Following every change in
        // height, with an animation, fed itself in a long conversation (each scroll measured
        // more rows, changing the height again) and froze the screen.
        .onChange(of: rows.last?.id) { _, _ in
            guard following else { return }
            withoutAnimation { position.scrollTo(id: Self.end, anchor: .bottom) }
        }
        // Older rows shown above yours: your place stays where it was.
        .onChange(of: shown.first?.id) { previous, _ in
            guard !following, let previous, shown.contains(where: { $0.id == previous }) else {
                return
            }
            withoutAnimation { position.scrollTo(id: previous, anchor: .top) }
        }
        // Scrolling yourself stops the following; letting go at the end starts it again.
        .onScrollPhaseChange { _, phase in
            scrolling = phase == .tracking || phase == .interacting
            if scrolling {
                following = false
            } else if distanceFromEnd == .atEnd {
                follow()
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
        // The composer rides in the conversation's bottom inset rather than beside it: when it grows
        // or shrinks (a long draft deleted), only the inset changes, not the scroll view's frame,
        // which made the whole conversation lay itself out again.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let problem = session.problem {
                    ProblemNotice(problem: problem, connectAgain: connectAgain)
                } else {
                    // While Ari waits for your answer, the composer takes it, as a secret if asked.
                    ComposerArea(
                        session: session, attached: $attached, attachProblem: $attachProblem,
                        working: working, stopping: conversation.pendingStop != nil,
                        asking: revealing ? nil : conversation.waitingAsk,
                        send: send, stop: stop, attach: attach, detach: detach
                    )
                    .equatable()
                    .frame(maxWidth: Rhythm.column)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(.ariBackground)
        }
        .background(.ariBackground)
        // The reading pace, moving on in a view of its own.
        .background { RevealDriver(model: reveal, session: session) }
        // New words to reveal, or a message that ended: the pace's state catches up.
        .onChange(of: conversation.revision, initial: true) { _, _ in
            reveal.sync(session.conversation)
        }
        .onChange(of: pose(revealing: revealing), initial: true) { _, pose in show(pose) }
        .onChange(of: liveStatus(revealing: revealing), initial: true) { _, next in hold(next) }
        .onChange(of: session.link, initial: true) { _, link in noticeLink(link) }
        .onChange(of: conversation.lastEndedTurn?.id) { _, _ in noticeEnd(conversation) }
        .onChange(of: working) { wasWorking, isWorking in
            if wasWorking, !isWorking, !following { repliedWhileAway = true }
        }
        // Ten seconds into a turn, a nudge when it's done starts to be worth offering.
        .task(id: conversation.turn?.id) {
            guard offersNotifications, conversation.turn != nil, !offering else { return }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled, session.conversation.turn != nil { offering = true }
        }
        // Tapping a reply's notification opens the conversation at that reply.
        .onChange(of: opening.wrappedValue) { _, message in
            guard let message else { return }
            following = false
            withAnimation(.smooth(duration: 0.4)) {
                position.scrollTo(id: message.rawValue, anchor: .topLeading)
            }
            opening.wrappedValue = nil
        }
    }

    /// How far you are from the end, in the three bands the screen cares about.
    private enum Distance: Equatable {
        /// Within 100 points: following resumes here, even while a reply grows.
        case atEnd
        case near
        /// More than 600 points up: far enough for the Latest pill.
        case far

        init(_ points: CGFloat) {
            self = points < 100 ? .atEnd : points > 600 ? .far : .near
        }
    }

    /// The marker after the last row.
    private static let end = "end"
    /// How many rows show at first, and how many more each time you reach the top.
    private static let window = 60
    private static let more = 40

    // MARK: - Rows

    fileprivate struct Row: Identifiable {
        enum Kind {
            case day(Date)
            case yours(Conversation.Entry)
            case ari(Conversation.Entry)
            case trail(Trail)
            /// Ari offers to tell you when it's done, once.
            case offer
            /// A turn that failed before writing anything.
            case failure(TurnID, ServerError?)
        }

        let id: String
        let kind: Kind
    }

    /// The conversation as it reads (messages, and Ari's trail between them), with the date at the
    /// start of each day.
    private func rows(_ conversation: Conversation) -> [Row] {
        let key = RowsCache.Key(
            revision: conversation.revision, held: reveal.held,
            offering: offering && offersNotifications)
        if cache.key == key { return cache.rows }
        let rows = makeRows(conversation)
        cache.key = key
        cache.rows = rows
        return rows
    }

    private func makeRows(_ conversation: Conversation) -> [Row] {
        var rows: [Row] = []
        var day: Date?
        for item in Timeline(conversation, reveal: reveal.reveal).items {
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
        if offering, offersNotifications { rows.append(Row(id: "offer", kind: .offer)) }
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
            ) {
                if !entry.attachments.isEmpty {
                    MessageAttachments(attachments: entry.attachments) {
                        await session.bytes(of: $0)
                    }
                }
            }
        case .ari(let entry):
            let text = conversation.visibleText(of: entry)
            let document = cache.document(entry.id, text)
            Paced(shown: reveal.shown(entry), length: text.utf16.count) { position in
                VStack(alignment: .leading, spacing: 8) {
                    if !text.isEmpty {
                        ReplyView(document: document, position: position)
                    }
                    if position == .infinity { footer(for: entry, in: conversation) }
                }
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
        case .offer:
            NotificationOffer(answer: answerOffer)
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

    /// Whatever you send while Ari waits answers it. A secret names the ask, and keeps no text.
    /// Returns whether it went, so the composer can clear.
    private func send(_ text: String) -> Bool {
        let asking = session.conversation.waitingAsk
        let secret = asking?.secret ?? false
        guard !Self.anyRefused(attached, in: session),
            session.send(
                text, answers: secret ? asking?.id : nil, secret: secret,
                attachments: secret ? [] : attached.map(\.id)) != nil
        else { return false }
        attached = []
        sent += 1
        scrollToEnd()
        return true
    }

    /// Files dropped on the conversation: each attaches, as if picked with the +.
    private func drop(_ urls: [URL]) {
        let room = AttachmentMaker.mostPerMessage - attached.count
        guard room > 0, session.problem == nil else { return }
        Task {
            for url in urls.prefix(room) where url.isFileURL {
                do {
                    attach(try await AttachmentMaker.file(at: url))
                } catch let error as AttachmentMaker.TooLarge {
                    attachProblem = "\(error.name) is larger than Ito accepts: up to 20 MB."
                } catch {
                    attachProblem = "Couldn't read \(url.lastPathComponent)."
                }
            }
        }
    }

    /// A photo or file you picked: it starts uploading at once.
    private func attach(_ attachment: PendingAttachment) {
        guard attached.count < AttachmentMaker.mostPerMessage else { return }
        attached.append(attachment)
        session.attach(attachment)
    }

    private func detach(_ attachment: AttachmentID) {
        attached.removeAll { $0.id == attachment }
        session.detach(attachment)
    }

    /// An attachment the server refused holds the message until you take it off.
    fileprivate static func anyRefused(_ attached: [PendingAttachment], in session: Session) -> Bool
    {
        attached.contains {
            if case .refused = session.uploads[$0.id] { true } else { false }
        }
    }

    /// You tapped one of an ask's options: its label is your answer.
    private func answer(_ ask: Ask, _ option: Ask.Option) {
        guard session.send(option.label, answers: ask.id) != nil else { return }
        scrollToEnd()
    }

    private func scrollToEnd() {
        follow()
        withAnimation(.smooth(duration: 0.4)) {
            position.scrollTo(id: Self.end, anchor: .bottom)
        }
    }

    private func follow() {
        following = true
        repliedWhileAway = false
        // Back at the end, the older rows shown on the way up can go.
        firstShown = nil
    }

    private func withoutAnimation(_ change: () -> Void) {
        var settle = Transaction(animation: nil)
        settle.disablesAnimations = true
        withTransaction(settle, change)
    }

    /// The rows on screen: the latest ones, from `firstShown` on. More are shown as you scroll up
    /// (see ``showEarlier(_:)``), and the oldest are let go again once you're back at the end.
    private func shownRows(_ rows: [Row]) -> ArraySlice<Row> {
        if let firstShown, let start = rows.firstIndex(where: { $0.id == firstShown }) {
            return rows[start...]
        }
        return rows.suffix(Self.window)
    }

    /// You reached the top of what's shown: show more of what Ari has, then ask the server for
    /// what came before.
    private func showEarlier(_ rows: [Row]) {
        let first = shownRows(rows).first?.id
        let start = rows.firstIndex(where: { $0.id == first }) ?? 0
        if start > 0 {
            firstShown = rows[max(0, start - Self.more)].id
            return
        }
        firstShown = first
        // Only once you've scrolled up: at the end, a short screen would otherwise page back
        // through the whole history by itself.
        guard !following, session.conversation.hasEarlierMessages, !session.isLoadingEarlier
        else { return }
        Task {
            await session.loadEarlier()
            // The page arrives above what you're reading: show some of it, keeping your place.
            let now = self.rows(session.conversation)
            if let index = now.firstIndex(where: { $0.id == first }), index > 0 {
                firstShown = now[max(0, index - Self.more)].id
            }
        }
    }

    /// Stop names the message the server is still writing, at how much of it is on screen.
    private func stop() {
        stops += 1
        let conversation = session.conversation
        if conversation.turn == nil, !reveal.isRevealing,
            let ask = conversation.waitingAsk
        {
            session.cancel(ask.id)
            return
        }
        session.stop(cut: reveal.stop(in: conversation))
    }

    // MARK: - Status and poses

    private func pose(revealing: Bool) -> Pose {
        if linkDown { return .offline }
        if let turn = session.conversation.turn {
            if session.conversation.pendingStop != nil { return .stopping }
            // Writing and adjusting come from the status; anything else from the newest step in the
            // turn, running or just ended, with its prop. Not the oldest one still running: a plan
            // stays open the whole turn and would hide everything after it.
            if let kind = turn.status?.kind, kind == .writing || kind == .adjusting {
                return Pose(kind: kind)
            }
            if let step = session.conversation.steps.last(where: { $0.turn == turn.id }),
                let pose = Pose(step: step)
            {
                return pose
            }
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

    /// Each pose stays at least a second, so its prop can be seen: steps can flip faster than that.
    /// Stopping, going offline and coming to rest show at once.
    private func show(_ next: Pose) {
        let wait = 1.1 - Date.now.timeIntervalSince(poseSince)
        guard wait > 0, ![.stopping, .offline, .resting].contains(next) else {
            if next != poses.current { poseSince = .now }
            poses.set(next)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            let latest = pose(revealing: reveal.isRevealing)
            if latest != poses.current {
                poses.set(latest)
                poseSince = .now
            }
        }
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
            let latest = liveStatus(revealing: reveal.isRevealing)
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
        guard !following, distanceFromEnd != .atEnd else { return nil }
        if working { return "Ari is writing" }
        if repliedWhileAway { return "Ari has replied" }
        return distanceFromEnd == .far ? "Latest" : nil
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

/// The composer with what you've attached. Its own view, holding the draft, so typing redraws only
/// the composer and not the whole conversation above it; and equatable, so the conversation's
/// changes (a step, each word of a reply) don't redraw the composer either. Its text field measures
/// itself with TextKit on every redraw, which grew costly enough to freeze long conversations.
private struct ComposerArea: View, Equatable {
    let session: Session
    @Binding var attached: [PendingAttachment]
    @Binding var attachProblem: String?
    let working: Bool
    /// Your Stop is on its way.
    let stopping: Bool
    /// What Ari waits for you to answer, if anything.
    let asking: Ask?
    let send: (String) -> Bool
    let stop: () -> Void
    let attach: (PendingAttachment) -> Void
    let detach: (AttachmentID) -> Void

    /// What you're writing. Saved a moment after you stop typing, and when Ari leaves the screen,
    /// so it survives Ari closing; saved on every keystroke, the field kept waiting on it.
    @State private var draft = UserDefaults.standard.string(forKey: "draft") ?? ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let secret = asking?.secret ?? false
        Composer(
            draft: $draft, role: role,
            prompt: asking.map(Self.takesTypedAnswer) == true ? "Answer Ari" : "Message Ari",
            secret: secret, send: submit, stop: stop
        ) {
            // A secret answer is only ever typed.
            if !secret {
                AttachButton(
                    room: AttachmentMaker.mostPerMessage - attached.count, add: attach,
                    problem: { attachProblem = $0 })
            }
        } above: {
            if !attached.isEmpty {
                AttachedStrip(attached: attached, uploads: session.uploads, remove: detach)
            }
            if let attachProblem {
                Text(attachProblem)
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                    .task(id: attachProblem) {
                        try? await Task.sleep(for: .seconds(4))
                        if !Task.isCancelled { self.attachProblem = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: attached)
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { saveDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraft() }
        }
        #if DEBUG
            .task {
                if let draft = DebugScript.draft { self.draft = draft }
            }
        #endif
    }

    private var role: ComposerRole {
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attached.isEmpty {
            return ConversationView.anyRefused(attached, in: session) ? .idle : .send
        }
        if working, !stopping { return .stop }
        // Stop while Ari waits for you cancels what it asked.
        return asking != nil ? .stop : .idle
    }

    private func submit() {
        guard send(draft) else { return }
        draft = ""
        saveDraft()
    }

    private func saveDraft() {
        UserDefaults.standard.set(draft, forKey: "draft")
    }

    /// Only what the composer shows: the closures are the conversation's own, the same each time.
    static func == (a: ComposerArea, b: ComposerArea) -> Bool {
        a.attached == b.attached && a.attachProblem == b.attachProblem && a.working == b.working
            && a.stopping == b.stopping && a.asking == b.asking
    }

    /// Whether an ask takes a typed answer. Any message still answers it, but the composer only
    /// invites one when the ask does.
    private static func takesTypedAnswer(_ ask: Ask) -> Bool {
        ask.allowsText || ask.options.isEmpty || ask.secret
    }
}

/// What the conversation screen keeps between frames. A class, so filling it in while drawing
/// doesn't ask SwiftUI to draw again.
private final class RowsCache {
    /// What the rows were worked out from: the conversation's changes, where the reveal holds
    /// steps back, and whether Ari offers notifications.
    struct Key: Equatable {
        let revision: Int
        let held: Int?
        let offering: Bool
    }

    var key: Key?
    var rows: [ConversationView.Row] = []
    private var documents: [MessageID: (text: String, document: ReplyDocument)] = [:]

    /// A reply's Markdown, read once for each text it has.
    func document(_ id: MessageID, _ text: String) -> ReplyDocument {
        if let kept = documents[id], kept.text == text { return kept.document }
        let document = ReplyDocument(markdown: text)
        documents[id] = (text, document)
        return document
    }
}
