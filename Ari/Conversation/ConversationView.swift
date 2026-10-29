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

    @State var reveal = RevealModel()
    /// The status line and the character's pose, paced for reading.
    @State var header = HeaderState()
    /// Photos and files on the message you're writing, uploading as you write.
    @State var attached: [PendingAttachment] = []
    /// Something you picked that can't be attached, said for a few seconds.
    @State var attachProblem: String?
    @State var sheet: SheetItem?
    /// The trail's runs and steps you've opened.
    @State var opened: Set<String> = []
    // Scrolled by message, not by edge: scrolling to an edge also shifts the content sideways.
    @State var position = ScrollPosition(idType: String.self)
    @State var distanceFromEnd = Distance.atEnd
    /// Whether your finger is on the conversation.
    @State var scrolling = false
    /// The topics and days of the conversation, to jump between.
    @State var showsTopics = Self.opensTopics
    /// Whether you've scrolled near the top of what's shown: more history comes in while you are.
    @State var nearTop = false
    /// The first row on screen, once you've scrolled back past the latest ones; `nil` shows the
    /// latest.
    @State var firstShown: String?
    /// Whether the conversation follows what arrives. It does while you're at the end, stops once
    /// you scroll up, and starts again when you come back to the end, send, or tap the pill.
    @State var following = true
    @State var repliedWhileAway = false
    /// A turn has run long enough that a nudge when it's done would help.
    @State var offering = false
    /// A linked page, open in place.
    @State var browsing: WebPage?
    /// A thing in motion, open full screen, and what it grew from.
    @State var openedMotion: OpenedMotion?
    @Namespace var motionSpace
    /// Rows and parsed replies, kept between frames: a reply revealing redraws the screen every
    /// frame, and working the whole conversation out again each time froze long ones.
    @State var cache = RowsCache()
    /// Each send and each Stop, for a light tap you can feel.
    @State var sent = 0
    @State var stops = 0
    /// Calls with Ari.
    @Environment(Talk.self) var talk: Talk?
    /// Whether the server can talk.
    @Environment(Voices.self) var voices: Voices?

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
    var screen: some View {
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
                    // While Ari waits for your answer, the composer takes it.
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

    static var opensTopics: Bool {
        #if DEBUG
            DebugScript.opensTopics
        #else
            false
        #endif
    }

    // MARK: - What you do

    /// Talk, where Ari can take a call: on the iPhone.
    var talkAction: (() -> Void)? {
        guard let talk else { return nil }
        return { talk.start() }
    }

    /// Whether the server can talk now, so Talk shows as ready.
    var talkReady: Bool {
        voices?.canTalk ?? false
    }

    /// Back to the call a block opened, when it's this phone's and still on.
    func returnToCall(_ call: Call) -> (() -> Void)? {
        guard let talk, call.isOn, talk.call?.id == call.id else { return nil }
        return { talk.showsCall = true }
    }

    /// Whatever you send while Ari waits answers it. Returns whether it went, so the composer can
    /// clear.
    func send(_ text: String) -> Bool {
        guard !Self.anyRefused(attached, in: session),
            session.send(text, attachments: attached.map(\.id)) != nil
        else { return false }
        attached = []
        sent += 1
        scrollToEnd()
        return true
    }

    /// Files dropped on the conversation: each attaches, as if picked with the +.
    func drop(_ urls: [URL]) {
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
    func attach(_ attachment: PendingAttachment) {
        guard attached.count < AttachmentMaker.mostPerMessage else { return }
        attached.append(attachment)
        session.attach(attachment)
    }

    func detach(_ attachment: AttachmentID) {
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
    func answer(_ ask: Ask, _ option: Ask.Option) {
        guard session.send(option.label) != nil else { return }
        scrollToEnd()
    }

    /// Stop ends the turn, and what Ari wrote shows at once. While Ari only waits for you, it
    /// cancels what Ari asked.
    func stop() {
        stops += 1
        let conversation = session.conversation
        if conversation.turn == nil, !reveal.isRevealing,
            let ask = conversation.waitingAsk
        {
            session.cancel(ask.id)
            return
        }
        reveal.stop(in: conversation)
        session.stop()
    }

    // MARK: - Status and poses

    func pose(revealing: Bool) -> Pose {
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

    func liveStatus(revealing: Bool) -> StatusText? {
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

}
