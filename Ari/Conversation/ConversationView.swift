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
    /// Where in the chat to go, from a thing in motion's "What changed".
    var openingPosition: Binding<Int?> = .constant(nil)
    /// Whether Ari may offer notifications, once a turn takes a while.
    var offersNotifications = false
    var answerOffer: (Bool) -> Void = { _ in }

    @State private var reveal = RevealModel()
    /// The status line and the character's pose, paced for reading.
    @State private var header = HeaderState()
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
    /// The topics and days of the conversation, to jump between.
    @State private var showsTopics = Self.opensTopics
    /// Whether you've scrolled near the top of what's shown: more history comes in while you are.
    @State private var nearTop = false
    /// The first row on screen, once you've scrolled back past the latest ones; `nil` shows the
    /// latest.
    @State private var firstShown: String?
    /// Whether the conversation follows what arrives. It does while you're at the end, stops once
    /// you scroll up, and starts again when you come back to the end, send, or tap the pill.
    @State private var following = true
    @State private var repliedWhileAway = false
    /// A turn has run long enough that a nudge when it's done would help.
    @State private var offering = false
    /// A linked page, open in place.
    @State private var browsing: WebPage?
    /// A thing in motion, open full screen, and what it grew from.
    @State private var openedMotion: OpenedMotion?
    @Namespace private var motionSpace
    /// Rows and parsed replies, kept between frames: a reply revealing redraws the screen every
    /// frame, and working the whole conversation out again each time froze long ones.
    @State private var cache = RowsCache()
    /// Each send and each Stop, for a light tap you can feel.
    @State private var sent = 0
    @State private var stops = 0
    /// Calls with Ari.
    @Environment(Talk.self) private var talk: Talk?
    /// Whether the server can talk.
    @Environment(Voices.self) private var voices: Voices?

    var body: some View {
        screen
            // The pinned line, compact lines and the trail open what's in motion over the chat.
            .environment(
                \.motionOpener,
                MotionOpener(namespace: motionSpace) { id, source in
                    openedMotion = OpenedMotion(id: id, source: source)
                }
            )
            .motionCover($openedMotion, in: motionSpace)
            // Files dropped on the conversation attach to the message you're writing.
            .dropDestination(for: URL.self) { urls, _ in drop(urls) }
            .sensoryFeedback(.impact(weight: .light), trigger: sent)
            .sensoryFeedback(.impact(weight: .medium), trigger: stops)
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
            .sheet(item: $sheet) { item in
                switch item {
                case .details(let error): DetailsSheet(error: error)
                case .selecting(let text): SelectTextSheet(text: text)
                case .fixingWord(let text):
                    FixWordSheet(text: text) { heard, meant in
                        await session.teach([.init(heard: heard, meant: meant)])
                    }
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
                .task {
                    guard let row = DebugScript.openRow else { return }
                    while !rows(session.conversation).contains(where: { $0.id == row }) {
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    open(at: row, in: rows(session.conversation))
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
                        // A comfortable reading width, inside a row as wide as the screen:
                        // scrolling to a row lines up its edge with the screen's, so a row starting
                        // at its margin slid the whole conversation sideways.
                        .frame(maxWidth: Rhythm.column, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .id(row.id)
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
            HeaderView(poses: header.poses, name: name, status: header.status) {
                showsTopics = true
            }
        }
        // Near the top, older history comes in, page after page, for as long as you stay there.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < 400
        } action: { _, near in
            nearTop = near
            if near { showEarlier(rows) }
        }
        .sheet(isPresented: $showsTopics) {
            TopicsSheet(
                marks: TopicsSheet.marks(in: rows),
                hasEarlier: session.conversation.hasEarlierMessages,
                loadEarlier: { await session.loadEarlier() }
            ) { id in
                showsTopics = false
                jump(to: id)
            }
            .presentationDetents([.medium, .large])
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
                    VStack(spacing: 0) {
                        if let talk, let notice = talk.notice, talk.call == nil {
                            TalkNotice(text: notice) { talk.notice = nil }
                        }
                        if let talk, let call = talk.call, !talk.showsCall {
                            OnCallBar(call: call) { talk.showsCall = true }
                        }
                        PinnedArea(holding: working)
                        ComposerArea(
                            session: session, attached: $attached, attachProblem: $attachProblem,
                            working: working, stopping: conversation.pendingStop != nil,
                            asking: revealing ? nil : conversation.waitingAsk,
                            send: send, stop: stop, attach: attach, detach: detach,
                            talk: talkAction, talkReady: talkReady
                        )
                        .equatable()
                    }
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
        .onChange(of: pose(revealing: revealing), initial: true) { _, pose in
            header.show(pose: pose) { self.pose(revealing: reveal.isRevealing) }
        }
        .onChange(of: liveStatus(revealing: revealing), initial: true) { _, next in
            header.show(status: next) { liveStatus(revealing: reveal.isRevealing) }
        }
        .onChange(of: session.link, initial: true) { _, link in
            header.notice(link: link) { session.link }
        }
        .onChange(of: conversation.lastEndedTurn?.id) { _, _ in
            if session.conversation.lastEndedTurn?.outcome == .stopped { header.noticeStopped() }
        }
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
            opening.wrappedValue = nil
            open(at: message.rawValue, in: rows)
        }
        .onChange(of: openingPosition.wrappedValue) { _, position in
            guard let position else { return }
            openingPosition.wrappedValue = nil
            jump(toPosition: position)
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
    private static var opensTopics: Bool {
        #if DEBUG
            DebugScript.opensTopics
        #else
            false
        #endif
    }

    private static let window = 60
    private static let more = 40

    // MARK: - Rows

    typealias Row = ConversationRow

    /// The conversation as it reads (messages, and Ari's trail between them), with the date at the
    /// start of each day.
    private func rows(_ conversation: Conversation) -> [Row] {
        let key = RowsCache.Key(
            revision: conversation.revision, held: reveal.held,
            offering: offering && offersNotifications)
        if cache.key == key { return cache.rows }
        let rows = RowsCache.make(conversation, reveal: reveal.reveal, offering: key.offering)
        cache.key = key
        cache.rows = rows
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row, in conversation: Conversation) -> some View {
        switch row.kind {
        case .day(let date):
            DayLabel(date: date)
        case .topic(let topic):
            TopicLabel(label: topic.label) { showsTopics = true }
        case .yours(let entry):
            YourMessage(
                text: entry.isSecret ? "••••••" : entry.text,
                tag: tag(for: entry, in: conversation),
                corrections: entry.spoken?.corrections ?? []
            ) {
                if !entry.attachments.isEmpty {
                    MessageAttachments(attachments: entry.attachments) {
                        await session.bytes(of: $0)
                    }
                }
            } footer: {
                if let spoken = entry.spoken {
                    SpokenFooter(
                        spoken: spoken, text: entry.text, bytes: { await session.bytes(of: $0) },
                        fixWord: { sheet = .fixingWord(entry.text) })
                }
            }
        case .call(let call):
            CallBlock(
                call: call, returnToCall: returnToCall(call),
                deleteAudio: { session.deleteAudio(of: call.id) })
        case .ari(let entry):
            let text = conversation.visibleText(of: entry)
            let document = cache.document(entry.id, text)
            Paced(shown: reveal.shown(entry), length: text.utf16.count) { position in
                VStack(alignment: .leading, spacing: 8) {
                    if !text.isEmpty {
                        ReplyView(document: document, position: position)
                            .environment(\.replyActions, replyActions(for: entry, in: conversation))
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

    /// What a reply's shapes can do here: tick its plans, fetch its pictures, and, while it's the
    /// latest thing said and Ari is idle, send one of its choices.
    private func replyActions(for entry: Conversation.Entry, in conversation: Conversation)
        -> ReplyActions
    {
        let latest =
            conversation.turn == nil && conversation.entries.last(where: \.isShown)?.id == entry.id
        let session = session
        return ReplyActions(
            ticks: entry.ticks,
            tick: { part, item, done in
                await session.tick(entry.id, part: part, item: item, done: done)
            },
            choose: latest
                ? { label in
                    guard session.send(label) != nil else { return }
                    scrollToEnd()
                } : nil,
            image: { await session.bytes(of: $0) })
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

    /// Talk, where Ari can take a call: on the iPhone.
    private var talkAction: (() -> Void)? {
        guard let talk else { return nil }
        return { talk.start() }
    }

    /// Whether the server can talk now, so Talk shows as ready.
    private var talkReady: Bool {
        voices?.canTalk ?? false
    }

    /// Back to the call a block opened, when it's this phone's and still on.
    private func returnToCall(_ call: Call) -> (() -> Void)? {
        guard let talk, call.isOn, talk.call?.id == call.id else { return nil }
        return { talk.showsCall = true }
    }

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
    static func anyRefused(_ attached: [PendingAttachment], in session: Session) -> Bool {
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

    /// Opens the conversation at a row, as from a tapped notification: an older one is shown first,
    /// since only the latest rows are on screen until you scroll back.
    private func open(at id: String, in rows: [Row]) {
        following = false
        if !shownRows(rows).contains(where: { $0.id == id }),
            let index = rows.firstIndex(where: { $0.id == id })
        {
            firstShown = rows[max(0, index - 2)].id
        }
        Task {
            // A moment for the newly shown rows to be laid out before scrolling to one.
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.4)) { position.scrollTo(id: id, anchor: .top) }
        }
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

    /// Goes to a topic or a day: older history comes in until it's there, then the conversation
    /// opens at it, and settles there once the rows above have their heights.
    private func jump(to id: String) {
        following = false
        Task {
            var rows = self.rows(session.conversation)
            while !rows.contains(where: { $0.id == id }), session.conversation.hasEarlierMessages {
                let before = rows.count
                await session.loadEarlier()
                rows = self.rows(session.conversation)
                if rows.count == before { break }
            }
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            firstShown = rows[max(0, index - 2)].id
            // The sheet goes, and the rows are laid out, before scrolling; and once more after,
            // when the rows above have settled their heights.
            try? await Task.sleep(for: .milliseconds(350))
            withoutAnimation { position.scrollTo(id: id, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(200))
            withoutAnimation { position.scrollTo(id: id, anchor: .top) }
        }
    }

    /// Goes to the message at a position, such as where Ari changed a thing in motion: older history
    /// comes in until it reaches that far back, then the conversation opens at it.
    private func jump(toPosition position: Int) {
        Task {
            while session.conversation.hasEarlierMessages,
                (session.conversation.entries.first?.position ?? 0) > position
            {
                let before = session.conversation.entries.count
                await session.loadEarlier()
                if session.conversation.entries.count == before { break }
            }
            guard
                let entry = session.conversation.entries.first(where: {
                    ($0.position ?? .max) >= position
                })
            else { return }
            jump(to: entry.id.rawValue)
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
        if header.linkDown { return .offline }
        if let turn = session.conversation.turn {
            if session.conversation.pendingStop != nil { return .stopping }
            // An app waits on your approval inside the turn: Ari is asking you, not working.
            if session.conversation.waitingAsk != nil { return .asking }
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
        if header.linkDown {
            return .quiet(session.link == .offline ? "No connection" : "Reconnecting")
        }
        let conversation = session.conversation
        if let turn = conversation.turn {
            if conversation.pendingStop != nil { return .status("Stopping", detail: nil) }
            return turn.status.map { .status($0.label, detail: $0.detail) }
        }
        if revealing { return .status("Writing", detail: nil) }
        if conversation.waitingAsk != nil { return .status("Waiting for you", detail: nil) }
        return header.stopped ? .quiet("Stopped") : nil
    }

    private func pillText(working: Bool) -> String? {
        guard !following, distanceFromEnd != .atEnd else { return nil }
        if working { return "Ari is writing" }
        if repliedWhileAway { return "Ari has replied" }
        return distanceFromEnd == .far ? "Latest" : nil
    }
}
