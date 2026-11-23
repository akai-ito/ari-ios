import Foundation
import Observation

/// Ari's live connection to one server: the conversation with Kumo and the Desk, kept up to date
/// from the event stream, and everything you ask of them. SwiftUI watches it directly; the waiting
/// (for the network, the server, a retry) happens in small lanes that hand their results back here.
///
/// - The **event stream** carries the conversation and the Desk on one connection. It resumes from
///   the last event applied, reconnects with backoff, and treats 45 seconds without even a ping as a
///   lost connection.
/// - The **outbox** saves each message on the device first, then sends one at a time, in order,
///   once the stream is live, retrying with the same id until the server has it.
/// - **Stop** has its own lane: never behind the outbox or a reconnect.
/// - **Try again** has its own lane too; the failed turn's id makes repeats safe.
/// - **Cancelling an ask** (Stop while it waits) has its own lane as well, and repeats are safe.
/// - **Calls** start and end on their own lane, in order; a call's stream carries the rest.
/// - **Where the phone is** (its time zone, and roughly its place) goes on its own lane too, only the
///   latest, retried until the server has it.
/// - **The Desk's answers** (a card, a guess, one of Kumo's plans moved or cancelled, Done and its
///   undo, a calendar event, today's work) are plain requests: you're watching for them, so they
///   say at once when they fail.
@MainActor
@Observable
public final class Session {
    /// The main chat as Ari shows it.
    public private(set) var conversation: Conversation
    /// The side threads you've opened, each a conversation of its own, fed by the same stream.
    public private(set) var threadConversations: [ThreadID: Conversation] = [:]
    /// Threads you started here before the server named them, and the thread each became.
    public private(set) var adopted: [ThreadID: ThreadID] = [:]
    /// Threads you're starting here, before the server has them: the main chat's message each
    /// replies to, or none for a new thread.
    public private(set) var drafts: [ThreadID: MessageID?] = [:]
    /// Threads you started here that hold your message while the server hasn't named them yet,
    /// such as one a recording started while it goes up, in the order you started them: the main
    /// chat shows a line for each meanwhile.
    public private(set) var waitingThreads: [ThreadID] = []
    /// The Desk, once the stream has said what's on it.
    public private(set) var desk: Desk?
    /// How getting started stands, once the stream or ``refreshOnboarding()`` has said.
    public private(set) var onboarding: Onboarding?
    /// What's wrong on the server right now, each with how to fix it; empty when nothing is. The
    /// snapshot and `problems.changed` keep it current.
    public private(set) var problems: [ServerProblem] = []
    /// How the event stream is doing.
    public private(set) var link: Link = .paused
    /// Something that needs you before Ari can carry on.
    public private(set) var problem: Problem?
    /// Whether a page of older messages is on its way.
    public private(set) var isLoadingEarlier = false
    /// Messages the server refused outright, which Ari won't retry. This needs a bug on one side.
    public private(set) var refusedMessages: [MessageID: RequestError] = [:]
    /// The server's voice, as the stream last said: for Talk to follow.
    public private(set) var voiceStatus: VoiceStatus?
    /// What's in motion, which follows the same stream.
    @ObservationIgnored public weak var motions: Motions?
    /// The pages Kumo made, kept current from the stream.
    @ObservationIgnored public weak var made: MadePages?
    /// Kumo's browser, as the snapshot and `browser.changed` last said.
    public private(set) var browser = Browser.idle
    /// Kumo's hands, which follow the browser from the same stream.
    @ObservationIgnored public weak var hands: Hands? {
        didSet {
            hands?.follow(browser)
            hands?.follow(desk: desk)
        }
    }

    public enum Link: Equatable, Sendable {
        /// The first attempt since ``start()``.
        case connecting
        /// The stream is open: what the server says arrives as it happens.
        case live
        /// The stream broke and Ari is trying again.
        case reconnecting
        /// There's no network; messages wait to send.
        case offline
        /// Ari isn't on screen, so the stream is closed.
        case paused
    }

    private struct StopRequest {
        /// `nil` until the turn it stops is announced.
        var turn: TurnID?
        /// Where that turn runs: the main chat, or a thread.
        var place: ThreadID?
    }

    public enum Problem: Equatable, Sendable {
        /// The server stopped accepting the token.
        case tokenRejected(ServerError?)
        /// The server now speaks a protocol version this Ari doesn't.
        case protocolMismatch(ProtocolMismatch)
    }

    /// The longest message the server takes, in characters.
    public static let maximumLength = 32_000

    @ObservationIgnored let client: ItoClient
    @ObservationIgnored private let outbox: OutboxStore
    @ObservationIgnored private let network: any NetworkPath
    @ObservationIgnored private let ticker: Ticker
    @ObservationIgnored private var queue: [SendMessage] = []
    /// Your Stop, until the server has it: for its turn, or for the next one to start.
    @ObservationIgnored private var stopRequest: StopRequest?
    @ObservationIgnored private var retries: [TurnID] = []
    @ObservationIgnored private var cancels: [AskID] = []
    @ObservationIgnored private var callRequests: [CallRequest] = []
    /// The device to register for notifications (or forget, with no registration), until the
    /// server has it.
    @ObservationIgnored private var deviceRequest: (id: String, registration: RegisterDevice?)?
    /// Where the phone roughly is, until the server has it: only the latest goes.
    @ObservationIgnored private var whereaboutsRequest: (device: String, whereabouts: Whereabouts)?
    /// Attachments still to upload, in the order you attached them.
    @ObservationIgnored private var uploadQueue: [PendingAttachment] = []

    /// Each attachment's upload, by id, for the composer to show.
    public private(set) var uploads: [AttachmentID: Upload] = [:]

    public enum Upload: Sendable, Equatable {
        case uploading
        case uploaded(Attachment)
        /// The server refused it, such as for being too large; its message says why.
        case refused(RequestError)
    }

    /// The recordings you sent, by attachment, as the server last said: for their cards.
    public internal(set) var recordings: [AttachmentID: Recording] = [:]
    /// Ari's big uploads: a message naming one waits for it, even across a restart, and is handed
    /// to them too, so it goes once the upload finishes even with Ari in the background.
    @ObservationIgnored public weak var bigUploads: BigUploads?
    /// Big uploads as the conversation shows them before the server has them.
    @ObservationIgnored private var bigAttachments: [AttachmentID: Attachment] = [:]
    /// Files Kumo showed, once fetched: a card scrolling back into view draws at once.
    @ObservationIgnored var shownFiles: [FileID: ShownFile] = [:]
    /// What the server takes, once asked.
    @ObservationIgnored var uploadList: UploadList?
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private var wantsSnapshot = false
    @ObservationIgnored private var lastHeard: Duration = .zero
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var readingTask: Task<Void, any Error>?
    @ObservationIgnored private var lanes: [Task<Void, Never>] = []
    @ObservationIgnored private var sleepers: [Int: (reasons: Wake, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var nextSleeper = 0
    @ObservationIgnored private let cache: AttachmentCache?
    /// The server this session talks to.
    public let address: ServerAddress
    /// Attachments being fetched, so two views asking at once make one request.
    @ObservationIgnored private var fetches: [AttachmentID: Task<Data?, Never>] = [:]
    /// Messages whose attachments went again because the server no longer had them, once each.
    @ObservationIgnored private var uploadedAgain: Set<MessageID> = []
    /// Threads being opened, and the events that arrived meanwhile, applied once they're open.
    @ObservationIgnored private var opening: [ThreadID: [Event]] = [:]

    /// - Parameters:
    ///   - conversation: Where to start: the cached conversation, or an empty one.
    ///   - outbox: Where waiting messages are saved. Messages left from an earlier run are sent
    ///     after ``start()``.
    ///   - cache: Where attachments' bytes are kept once fetched or attached; with none, they're
    ///     fetched each time.
    public convenience init(
        connection: Connection, conversation: Conversation = Conversation(), outbox: OutboxStore,
        cache: AttachmentCache? = nil, transport: any Transport = URLSessionTransport(),
        network: any NetworkPath = SystemNetworkPath(),
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.init(
            address: connection.address, token: connection.token, conversation: conversation,
            outbox: outbox, cache: cache, transport: transport, network: network, clock: clock)
    }

    /// A session with the server at `address`, for when who answered there isn't known, such as
    /// when an older Ari saved it in a shape this one can't read.
    public init(
        address: ServerAddress, token: Token, conversation: Conversation = Conversation(),
        outbox: OutboxStore, cache: AttachmentCache? = nil,
        transport: any Transport = URLSessionTransport(),
        network: any NetworkPath = SystemNetworkPath(),
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.conversation = conversation
        self.address = address
        self.outbox = outbox
        self.cache = cache
        self.network = network
        ticker = Ticker(clock)
        client = ItoClient(address: address, token: token, transport: transport)
    }

    // MARK: - Lifecycle

    /// Ari is on screen: connect, keep the stream live, and send whatever is waiting.
    public func start() {
        if lanes.isEmpty {
            let waiting = (try? outbox.load()) ?? []
            let named = Set(waiting.flatMap { $0.attachments ?? [] })
            for upload in bigUploads?.store.all() ?? [] where named.contains(upload.id) {
                bigUploadChanged(upload)
            }
            for attachment in outbox.attachments() where uploads[attachment.id] == nil {
                // A draft doesn't survive a restart, so what no waiting message names goes.
                guard named.contains(attachment.id) else {
                    outbox.removeAttachment(attachment.id)
                    continue
                }
                uploads[attachment.id] = .uploading
                uploadQueue.append(attachment)
            }
            for message in waiting where !queue.contains(message) {
                // Photos already uploaded show once the server accepts the message.
                let waiting = (message.attachments ?? []).compactMap { id in
                    uploadQueue.first { $0.id == id }?.attachment ?? bigAttachments[id]
                }
                // A message for a thread shows there once the thread is open and the server has it.
                // One that starts a thread, such as a recording still going up, starts it here again.
                if message.thread == nil, message.replyTo == nil, message.newThread != true {
                    conversation.send(message.id, text: message.text, attachments: waiting)
                } else if message.thread == nil {
                    let draft = startThread(
                        replyingTo: message.newThread == true ? nil : message.replyTo)
                    threadConversations[draft]?.send(
                        message.id, text: message.text, attachments: waiting)
                    holding(in: draft)
                }
                queue.append(message)
            }
            let network = network
            lanes = [
                Task { [weak self] in
                    for await online in network.updates() {
                        guard let self else { return }
                        self.setOnline(online)
                    }
                },
                Task { await self.runOutbox() },
                Task { await self.runStops() },
                Task { await self.runRetries() },
                Task { await self.runCancels() },
                Task { await self.runDevice() },
                Task { await self.runWhereabouts() },
                Task { await self.runUploads() },
                Task { await self.runCalls() },
            ]
        }
        guard streamTask == nil else { return }
        streamTask = Task { await self.runStream() }
    }

    /// Ari has left the screen: close the stream. Waiting messages stay saved, and a Stop still goes.
    public func pause() {
        streamTask?.cancel()
        streamTask = nil
        readingTask?.cancel()
        link = .paused
    }

    /// Ends everything. Waiting messages stay in the outbox for next time.
    public func close() {
        pause()
        for lane in lanes { lane.cancel() }
        lanes = []
    }

    // MARK: - What you do

    /// You tapped Send, in the chat or from the Desk. Your message shows at once, is
    /// saved on the device, and goes as soon as it can. Returns its id, or `nil` if there's nothing
    /// to send or it's longer than the server takes.
    ///
    /// While an ask waits, any message answers it, a tapped option included.
    ///
    /// - Parameters:
    ///   - id: Its permanent id and retry key; a new random UUID unless a test chooses one.
    ///   - attachments: Photos and files attached with ``attach(_:)``. The message goes once
    ///     they're all on the server; the text may then be empty.
    ///   - done: The line of Done it replies to, telling Kumo it got that one wrong.
    ///   - place: The thread it goes into, or `nil` for the main chat. A thread you're starting
    ///     here (``startThread(replyingTo:)``) is named by the server once it has the message. A
    ///     recording for the main chat starts a thread of its own instead, where Kumo's take on it
    ///     comes too; ``draft(holding:)`` says which.
    ///   - replyingTo: Inside a thread, the message you're replying to, which it quotes.
    @discardableResult
    public func send(
        _ text: String, id: MessageID = MessageID(UUID().uuidString.lowercased()),
        attachments: [AttachmentID] = [], done: DoneID? = nil, in place: ThreadID? = nil,
        replyingTo: MessageID? = nil
    ) -> MessageID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
            text.count <= Self.maximumLength
        else { return nil }
        let shown = attachments.compactMap(attachment)
        var place = place
        if place == nil, conversation[id] == nil, Self.startsThread(carrying: shown) {
            // Sent again, as a shared recording is each time Ari comes back, it stays where it is.
            place =
                threadConversations.first { $0.value[id] != nil }?.key
                ?? startThread(replyingTo: nil)
        }
        let thread = resolved(place)
        let draft = thread.flatMap { drafts[$0] }
        let message = SendMessage(
            id: id, text: text, attachments: attachments, done: done,
            thread: draft == nil ? thread : nil, replyTo: replyingTo ?? draft ?? nil,
            newThread: draft.map { $0 == nil } ?? false)
        if let thread {
            let quotes = replyingTo.flatMap { quote(of: $0, in: thread) }
            threadConversations[thread, default: Conversation(place: thread)].send(
                id, text: text, attachments: shown, quotes: quotes)
            holding(in: thread)
        } else {
            conversation.send(id, text: text, attachments: shown)
        }
        for big in attachments where bigAttachments[big] != nil {
            bigUploads?.send(message, after: big)
        }
        try? outbox.add(message)
        if !queue.contains(message) { queue.append(message) }
        wake(.outbox)
        return id
    }

    /// You tapped a button on one of Kumo's cards, such as a proposed change or Use in draft: your
    /// message, its words and then a block saying exactly what you tapped, goes into the
    /// conversation the card is in, the main chat (`nil`) or its thread, so Kumo acts and answers
    /// there, however long after the card came.
    @discardableResult
    public func send(_ tap: YourTap, saying words: String, in place: ThreadID?) -> MessageID? {
        send(tap.message(saying: words), in: place)
    }

    /// What your reply quotes: a line of the message, as the server writes it.
    private func quote(of message: MessageID, in thread: ThreadID) -> Quote? {
        guard let entry = threadConversations[thread]?[message] else { return nil }
        return Quote(message: message, text: entry.line)
    }

    // MARK: - Threads

    /// The main chat (`nil`), or a thread's conversation: empty until it's opened.
    public func conversation(in place: ThreadID?) -> Conversation {
        guard let thread = resolved(place) else { return conversation }
        return threadConversations[thread] ?? Conversation(place: thread)
    }

    /// The thread a place is now: a thread you started here becomes the one the server named.
    public func resolved(_ place: ThreadID?) -> ThreadID? {
        place.map { adopted[$0] ?? $0 }
    }

    /// Replying to `message` in the main chat opens the thread under it, or starts one; with no
    /// message, a new thread of your own. Returns where to show it: the thread, or a draft the
    /// server names once your first message is there.
    public func startThread(replyingTo message: MessageID?) -> ThreadID {
        if let message, let existing = conversation.thread(hangingFrom: message) {
            return existing.id
        }
        let draft = ThreadID("draft-\(UUID().uuidString.lowercased())")
        drafts[draft] = .some(message)
        threadConversations[draft] = Conversation(place: draft)
        return draft
    }

    /// A message went into `thread`: one you're starting here waits for the server to name it.
    private func holding(in thread: ThreadID) {
        guard drafts[thread] != nil, !waitingThreads.contains(thread) else { return }
        waitingThreads.append(thread)
    }

    /// Whether a message carrying these starts a thread of its own when it's for the main chat: a
    /// recording does, so Kumo's take on it has a place of its own, as the server's follow-up
    /// expects.
    public nonisolated static func startsThread(carrying attachments: [Attachment]) -> Bool {
        attachments.contains { $0.kind == .audio }
    }

    /// Opens a thread: its latest messages, steps and running turn. What the stream brings
    /// meanwhile applies once it's open.
    public func openThread(_ place: ThreadID) async {
        guard let thread = resolved(place), drafts[thread] == nil, opening[thread] == nil else {
            return
        }
        opening[thread] = []
        defer { opening[thread] = nil }
        do {
            let page = try await client.thread(thread)
            var opened = threadConversations[thread] ?? Conversation(place: thread)
            opened.replace(with: page)
            for event in opening[thread] ?? [] { opened.apply(event) }
            threadConversations[thread] = opened
            conversation.update(page.thread)
        } catch {
            // It stays as it was; opening it again tries again.
        }
    }

    /// Every thread, for Threads by day: open ones, then done ones newest first, or those holding
    /// all of `query`'s words.
    public func threads(matching query: String = "", before: ThreadID? = nil)
        async throws(RequestError) -> ThreadList
    {
        let listed = try await client.threads(matching: query, before: before)
        conversation.learn(listed.open + listed.threads)
        return listed
    }

    /// Renames a thread, or marks it done or open.
    public func change(_ place: ThreadID, _ change: ThreadChange) async throws(RequestError) {
        guard let thread = resolved(place), drafts[thread] == nil else { return }
        learn(try await client.change(thread, change))
    }

    /// You've seen what's new in a thread, on every app.
    public func see(_ place: ThreadID) async {
        guard let thread = resolved(place), drafts[thread] == nil,
            conversation(in: thread).thread?.news != nil
                || conversation.threads[thread]?.news != nil,
            let seen = try? await client.see(thread)
        else { return }
        learn(seen)
    }

    /// Moves a message into a thread, or back to the main chat with `nil`.
    public func move(_ message: MessageID, to place: ThreadID?) async throws(RequestError) {
        let thread = resolved(place)
        guard thread.map({ drafts[$0] == nil }) ?? true else { return }
        _ = try await client.move(message, to: thread)
    }

    private func learn(_ thread: SideThread) {
        conversation.update(thread)
        threadConversations[thread.id]?.update(thread)
    }

    /// Applies `change` to the main chat and every open thread.
    private func updateEach(_ change: (inout Conversation) -> Void) {
        change(&conversation)
        for key in threadConversations.keys { change(&threadConversations[key]!) }
    }

    /// The thread you're starting here that holds your message `id`, if one does: where a recording
    /// sent to the main chat went.
    public func draft(holding id: MessageID) -> ThreadID? {
        drafts.keys.first { threadConversations[$0]?[id] != nil }
    }

    /// The server put your first message of a draft in `thread`: the draft becomes it.
    private func adopt(_ draft: ThreadID, as thread: ThreadID) {
        guard var conversation = threadConversations.removeValue(forKey: draft) else { return }
        conversation.adopt(thread)
        if let existing = threadConversations[thread] { conversation = existing }
        threadConversations[thread] = conversation
        drafts[draft] = nil
        if waitingThreads.contains(draft) { waitingThreads.removeAll { $0 == draft } }
        adopted[draft] = thread
        Task { await self.openThread(thread) }
    }

    /// An attachment as the conversation shows it, once uploaded or while it waits to be.
    private func attachment(_ id: AttachmentID) -> Attachment? {
        if case .uploaded(let uploaded) = uploads[id] { return uploaded }
        return uploadQueue.first { $0.id == id }?.attachment ?? bigAttachments[id]
    }

    /// A big upload moved on: a message naming it goes once it's an attachment, and can't once the
    /// server refused it. Its progress is ``BigUploads``'s to show.
    public func bigUploadChanged(_ upload: BigUpload) {
        bigAttachments[upload.id] = upload.attachment
        let now: Upload =
            switch upload.state {
            case .sending: .uploading
            case .finished(let attachment): .uploaded(attachment)
            case .refused(let error): .refused(.refused(status: 400, error: error, retryAfter: nil))
            }
        guard uploads[upload.id] != now else { return }
        uploads[upload.id] = now
        wake(.upload)
    }

    /// You attached a photo or file: it starts uploading at once, while you write, saved on the
    /// device until the server has it.
    public func attach(_ attachment: PendingAttachment) {
        guard uploads[attachment.id] == nil else { return }
        try? outbox.add(attachment)
        cache?.keep(attachment.bytes, for: attachment.id)
        uploads[attachment.id] = .uploading
        uploadQueue.append(attachment)
        wake(.upload)
    }

    /// You removed an attachment before sending. It may already be on the server, unused; the
    /// server forgets unused uploads after a day.
    public func detach(_ attachment: AttachmentID) {
        if bigAttachments.removeValue(forKey: attachment) != nil, let bigUploads {
            Task { await bigUploads.cancel(attachment) }
        }
        uploadQueue.removeAll { $0.id == attachment }
        uploads[attachment] = nil
        outbox.removeAttachment(attachment)
    }

    /// An attachment's bytes, for showing it: kept on this device, or fetched once and kept.
    public func bytes(of attachment: AttachmentID) async -> Data? {
        if let kept = cache?.bytes(of: attachment) { return kept }
        if let waiting = uploadQueue.first(where: { $0.id == attachment }) { return waiting.bytes }
        if let fetching = fetches[attachment] { return await fetching.value }
        let client = client
        let fetching = Task { try? await client.attachmentBytes(attachment) }
        fetches[attachment] = fetching
        let bytes = await fetching.value
        fetches[attachment] = nil
        if let bytes { cache?.keep(bytes, for: attachment) }
        return bytes
    }

    /// You answered from a notification or Siri, with Ari closed or in the background: the message
    /// goes at once, without waiting for the event stream, and stays in the outbox until the server
    /// has it, so a failed attempt still goes next time Ari opens. Returns whether the server has
    /// it.
    @discardableResult
    public func sendFromNotification(
        _ text: String, id: MessageID = MessageID(UUID().uuidString.lowercased()),
        in thread: ThreadID? = nil
    ) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= Self.maximumLength
        else { return false }
        let message = SendMessage(id: id, text: text, thread: thread)
        if let thread {
            threadConversations[thread]?.send(id, text: text)
        } else {
            conversation.send(id, text: text)
        }
        try? outbox.add(message)
        if !queue.contains(message) { queue.append(message) }
        do {
            confirm(try await client.send(message))
            finish(message)
            return true
        } catch {
            return false
        }
    }

    /// Notifications are allowed: register this device, with its push token and notification key,
    /// so the server can reach it while you're not looking. Call it again when either changes.
    public func register(device: String, _ registration: RegisterDevice) {
        deviceRequest = (device, registration)
        wake(.device)
    }

    /// Notifications are turned off here: the server forgets this device.
    public func unregister(device: String) {
        deviceRequest = (device, nil)
        wake(.device)
    }

    /// Where the phone roughly is: its time zone, and its place when you allow it. Only the latest
    /// goes, as soon as it can, and again after a failure that may pass.
    public func report(_ whereabouts: Whereabouts, device: String) {
        guard whereaboutsRequest?.whereabouts != whereabouts else { return }
        whereaboutsRequest = (device, whereabouts)
        wake(.whereabouts)
    }

    /// You started a call: it starts on the server as soon as it can. Returns its id, for its
    /// stream and its end.
    @discardableResult
    public func startCall(id: CallID = CallID(UUID().uuidString.lowercased())) -> CallID {
        callRequests.append(.start(id))
        wake(.call)
        return id
    }

    /// You ended the call.
    public func endCall(_ id: CallID) {
        guard !callRequests.contains(.end(id)) else { return }
        callRequests.append(.end(id))
        wake(.call)
    }

    /// You deleted a call's audio from its block: the recordings go, the words stay.
    public func deleteAudio(of id: CallID) {
        guard !callRequests.contains(.deleteAudio(id)) else { return }
        callRequests.append(.deleteAudio(id))
        wake(.call)
    }

    /// A call's stream to the server: your voice up, and Kumo's voice and the call's state down.
    public func callStream(_ call: CallID) -> CallStream {
        let client = client
        return CallStream(connect: { client.callStream(call) })
    }

    /// You tapped Stop while an ask waited: it settles at once, and the cancel goes on its own lane.
    public func cancel(_ ask: AskID) {
        guard !cancels.contains(ask) else { return }
        let place = ([conversation] + Array(threadConversations.values)).first {
            $0[ask: ask]?.outcome == nil
        }
        guard let place else { return }
        if let thread = place.place {
            threadConversations[thread]?.cancel(ask)
        } else {
            conversation.cancel(ask)
        }
        cancels.append(ask)
        wake(.cancel)
    }

    /// You tapped Stop. The request goes on its own lane, even before the stream is back, and the
    /// reply keeps what Kumo had written. Tapped before the turn is announced, it goes as soon as it
    /// is.
    public func stop(in place: ThreadID? = nil) {
        let thread = resolved(place)
        let stopping = conversation(in: thread)
        if let turn = stopping.turn?.id {
            guard stopRequest?.turn != turn else { return }
            if let thread {
                threadConversations[thread]?.stop(turn: turn)
            } else {
                conversation.stop(turn: turn)
            }
            stopRequest = StopRequest(turn: turn, place: thread)
        } else if stopping.entries.last?.role == .user {
            stopRequest = StopRequest(turn: nil, place: thread)
        } else {
            return
        }
        wake(.stop)
    }

    /// You tapped Try again on the failed `turn`. Tapping twice is safe: the server starts one
    /// attempt.
    public func tryAgain(_ turn: TurnID) {
        updateEach { $0.retry(turn: turn) }
        retries.append(turn)
        wake(.retry)
    }

    /// You scrolled near the top: fetch the page of messages before the oldest Ari has.
    public func loadEarlier(limit: Int = 50, in place: ThreadID? = nil) async {
        let thread = resolved(place)
        let earlier = conversation(in: thread)
        guard earlier.hasEarlierMessages, !isLoadingEarlier,
            let oldest = earlier.entries.first, oldest.delivery != .sending
        else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await client.messages(before: oldest.id, limit: limit)
            if let thread {
                threadConversations[thread]?.insertEarlier(page, before: oldest.id)
            } else {
                conversation.insertEarlier(page, before: oldest.id)
            }
        } catch {
            // The server no longer has that message: Ari's view is stale, so replace it.
            if error.status == 404 {
                wantsSnapshot = true
                readingTask?.cancel()
            }
        }
    }

    // MARK: - The Desk

    /// You answered a card: with one of its options, the times you ticked, or words. It shows the
    /// box at work on it until the Desk says it's done. Answered on its card in a thread (`place`),
    /// anything Kumo says about it goes there.
    public func answer(_ card: CardID, _ answer: CardAnswer, in place: ThreadID? = nil)
        async throws(RequestError)
    {
        let waiting = desk?.waiting.first { $0.id == card }
        // A one-tap card answers in the thread its task lives in, wherever you tapped it: Kumo
        // tells you there how pressing went.
        let place = waiting?.commit?.thread ?? place
        // A thread you're starting here has no name on the server yet, so it can't be named.
        let thread = resolved(place).flatMap { drafts[$0] == nil ? $0 : nil }
        let result = try await client.answer(card, answer, thread: thread)
        desk = desk?.replacing(card: result.card)
        if let waiting, waiting.kind == .commit, let option = answer.option,
            waiting.options.contains(where: { $0.label == option && $0.acts })
        {
            hands?.pressing(waiting)
        }
    }

    /// You answered one of Kumo's guesses at your day: it shows as yours at once, no longer a
    /// guess, until the Desk says how it is.
    public func answerGuess(_ item: CalendarItemID, _ answer: GuessAnswer)
        async throws(RequestError)
    {
        let answered = try await client.answerGuess(item, answer)
        desk = desk?.replacing(item: answered)
    }

    /// Kumo's work today, or on another local day: what it handled and what it cleared, with the
    /// areas it's learning.
    public func work(day: String? = nil) async throws(RequestError) -> KumoWork {
        try await client.work(day: day)
    }

    /// You said Kumo got something wrong, with or without words. Returns the entry, corrected
    /// (and undone, where it could be).
    @discardableResult
    public func correct(_ entry: DoneID, text: String? = nil) async throws(RequestError)
        -> DoneEntry
    {
        try await client.correct(entry, text: text)
    }

    /// You pulled the Desk down: ask for all of it again.
    public func refreshDesk() async throws(RequestError) {
        desk = try await client.desk()
    }

    /// A page of what Kumo did without you, newest first: the latest, or those before an entry.
    public func done(before entry: DoneID? = nil, limit: Int = 50) async throws(RequestError)
        -> DonePage
    {
        try await client.done(before: entry, limit: limit)
    }

    /// You undid something Kumo did. Returns the entry, marked undone in its text.
    @discardableResult
    public func undo(_ entry: DoneID) async throws(RequestError) -> DoneEntry {
        try await client.undo(entry)
    }

    /// Asks for all of Kumo's plans again, such as when What I'm up to opens.
    public func refreshPlans() async throws(RequestError) {
        let plans = try await client.wakeUps()
        desk = desk?.replacing(plans: plans)
    }

    /// You moved one of Kumo's plans, changed how it repeats, or reworded it. It shows as it is
    /// now at once, until the Desk says how it is.
    @discardableResult
    public func change(_ plan: WakeUpID, _ change: WakeUpChange) async throws(RequestError)
        -> WakeUp
    {
        let changed = try await client.changeWakeUp(plan, change)
        desk = desk?.replacing(plan: changed)
        return changed
    }

    /// You cancelled one of Kumo's plans. It leaves the Desk at once; Kumo doesn't set it again
    /// unasked.
    public func cancel(_ plan: WakeUpID) async throws(RequestError) {
        do throws(RequestError) {
            try await client.cancelWakeUp(plan)
        } catch {
            // Already gone, such as one that came due meanwhile, is cancelled too.
            guard error.status == 404 else { throw error }
        }
        desk = desk?.removing(plan: plan)
    }

    /// You tapped Add to calendar: the box writes the event into your calendar. Returns it as the
    /// calendar holds it.
    @discardableResult
    public func addEvent(_ event: NewCalendarEvent) async throws(RequestError) -> CalendarItem {
        try await client.addEvent(event)
    }

    /// You moved one of Kumo's blocks on your day. It shows where it is now at once, until the
    /// Desk says how it is.
    public func move(_ item: CalendarItemID, to times: EventMove) async throws(RequestError) {
        let moved = try await client.moveEvent(item, to: times)
        desk = desk?.replacing(item: moved)
    }

    /// You removed one of Kumo's blocks from your day. It leaves the Desk at once.
    public func remove(_ item: CalendarItemID) async throws(RequestError) {
        do throws(RequestError) {
            try await client.removeEvent(item)
        } catch {
            // Already gone is removed too.
            guard error.status == 404 else { throw error }
        }
        desk = desk?.removing(item: item)
    }

    // MARK: - Getting started

    /// Asks where getting started stands, which the snapshot and `onboarding.changed` also say.
    public func refreshOnboarding() async throws(RequestError) {
        onboarding = try await client.onboarding()
    }

    /// You said a belief is still true, or corrected it. Its answer follows in
    /// `onboarding.changed`.
    public func answerBelief(_ belief: BeliefID, answer: BeliefAnswer) async throws(RequestError) {
        try await client.answerBelief(belief, answer: answer)
    }

    /// You've seen what Kumo found, so getting started is over. It shows as done here at once;
    /// `onboarding.changed` says so to every other device.
    public func finishOnboarding() async throws(RequestError) {
        onboarding = try await client.finishOnboarding()
    }

    /// Asks what's wrong on the server, which the snapshot and `problems.changed` also say.
    public func refreshProblems() async throws(RequestError) {
        problems = try await client.problems().problems
    }

    /// You want to see getting started again. It opens here at once, from the start; Kumo asks
    /// again and reads only an account you connect now.
    public func replayOnboarding() async throws(RequestError) {
        onboarding = try await client.replayOnboarding()
    }

    // MARK: - The event stream

    private func runStream() async {
        var failures = 0
        var wasLive = false
        while !Task.isCancelled, problem == nil {
            guard isOnline else {
                link = .offline
                await nap(until: .network)
                continue
            }
            link = failures == 0 && !wasLive ? .connecting : .reconnecting
            do {
                try await follow()
                failures = 0
                wasLive = true
                continue
            } catch {
                switch error {
                case .refused(401, let refusal, _):
                    problem = .tokenRejected(refusal)
                case .protocolMismatch(let version):
                    problem = .protocolMismatch(ProtocolMismatch(server: [version]))
                default:
                    break
                }
            }
            guard !Task.isCancelled, problem == nil else { break }
            failures += 1
            link = isOnline ? .reconnecting : .offline
            await nap(Self.reconnectDelay(after: failures), until: .network)
        }
    }

    /// Opens the stream and applies what it brings until it ends, goes silent for 45 seconds, or
    /// needs a snapshot.
    private func follow() async throws(RequestError) {
        let cursor = wantsSnapshot || conversation.needsSnapshot ? nil : conversation.cursor
        let stream = try await client.events(after: cursor)
        link = .live
        lastHeard = ticker.now()
        wake(.live)
        let feed = EventFeed.items(from: stream.body)
        let reading = Task {
            for try await item in feed {
                lastHeard = ticker.now()
                guard case .event(let event) = item else { continue }
                receive(event)
                if conversation.needsSnapshot { return }
            }
        }
        readingTask = reading
        let watchdog = Task { [ticker] in
            while !Task.isCancelled {
                let silence = ticker.now() - lastHeard
                if silence >= Self.silenceLimit {
                    reading.cancel()
                    return
                }
                try? await ticker.sleep(Self.silenceLimit - silence)
            }
        }
        defer { watchdog.cancel() }
        _ = await withTaskCancellationHandler {
            await reading.result
        } onCancel: {
            reading.cancel()
        }
    }

    private func receive(_ event: Event) {
        if case .messageAccepted(let accepted) = event.payload,
            let thread = accepted.message.thread,
            let draft = draft(holding: accepted.message.id)
        {
            adopt(draft, as: thread)
        }
        conversation.apply(event)
        for key in threadConversations.keys {
            threadConversations[key]!.apply(event)
            // A thread that missed something, or saw a snapshot, opens again from the server.
            if threadConversations[key]!.needsSnapshot { Task { await self.openThread(key) } }
        }
        for key in opening.keys { opening[key]?.append(event) }
        motions?.apply(event)
        made?.apply(event)
        switch event.payload {
        case .snapshot(let snapshot):
            desk = snapshot.desk
            hands?.follow(desk: snapshot.desk)
            // The browser's changes are compacted: no browser in the snapshot means it's idle.
            browser = snapshot.browser ?? .idle
            hands?.follow(browser)
            onboarding = snapshot.onboarding
            problems = snapshot.problems ?? []
            wantsSnapshot = false
            // Recordings' changes are compacted, so a snapshot means asking again.
            refreshRecordings()
        case .problemsChanged(let changed):
            problems = changed.problems
        case .deskChanged(let changed):
            desk = changed.desk
            hands?.follow(desk: changed.desk)
        case .browserChanged(let changed):
            browser = changed.browser
            hands?.follow(changed.browser)
        case .recordingChanged(let changed):
            recordings[changed.recording.attachment] = changed.recording
        case .onboardingChanged(let changed):
            onboarding = changed.onboarding
        case .voiceStatus(let status):
            voiceStatus = status
        case .turnStarted(let started):
            if let request = stopRequest, request.turn == nil, request.place == started.thread {
                if let thread = started.thread {
                    threadConversations[thread]?.stop(turn: started.turn)
                } else {
                    conversation.stop(turn: started.turn)
                }
                stopRequest = StopRequest(turn: started.turn, place: started.thread)
                wake(.stop)
            }
        default:
            break
        }
    }

    private func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if !online {
            readingTask?.cancel()
            if streamTask != nil { link = .offline }
        }
        wake(.network)
    }

    // MARK: - The lanes

    private func runOutbox() async {
        var failures = 0
        while !Task.isCancelled {
            guard let message = queue.first else {
                await nap(until: .outbox)
                continue
            }
            guard link == .live, problem == nil else {
                await nap(until: .live)
                continue
            }
            // A message goes once its attachments are on the server.
            let attached = message.attachments ?? []
            if let refused = attached.lazy.compactMap({ self.refusal(of: $0) }).first {
                refusedMessages[message.id] = refused
                finish(message)
                continue
            }
            if attached.contains(where: { uploads[$0] == .uploading }) {
                await nap(until: .upload)
                continue
            }
            do {
                confirm(try await client.send(message))
                finish(message)
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.sendDelay(after: failures, error), until: [.network, .live])
                } else if error.status == 401 {
                    problem = .tokenRejected(nil)
                } else if error.serverError?.code == .attachmentMissing,
                    uploadedAgain.insert(message.id).inserted, uploadAgain(message)
                {
                    // An upload left a day before sending is gone: it goes again, then the message.
                    continue
                } else {
                    refusedMessages[message.id] = error
                    finish(message)
                }
            }
        }
    }

    /// Uploads a message's attachments again, under the same ids, from the bytes kept in the
    /// outbox. Those the server still has answer at once and change nothing.
    private func uploadAgain(_ message: SendMessage) -> Bool {
        let named = message.attachments ?? []
        let kept = outbox.attachments().filter { named.contains($0.id) }
        guard kept.count == named.count else { return false }
        for attachment in kept where !uploadQueue.contains(where: { $0.id == attachment.id }) {
            uploads[attachment.id] = .uploading
            uploadQueue.append(attachment)
        }
        wake(.upload)
        return true
    }

    /// The server has your message: it shows as sent where it is. A draft's first message names the
    /// thread the draft becomes.
    private func confirm(_ result: MessageResult) {
        if let thread = result.message.thread, let draft = draft(holding: result.message.id) {
            adopt(draft, as: thread)
        }
        updateEach { $0.confirm(result) }
    }

    /// The message went, or can't: it, and the bytes of its attachments, leave the outbox.
    private func finish(_ message: SendMessage) {
        queue.removeAll { $0.id == message.id }
        try? outbox.remove(message.id)
        for attachment in message.attachments ?? [] { outbox.removeAttachment(attachment) }
        wake(.outbox)
    }

    private func refusal(of attachment: AttachmentID) -> RequestError? {
        if case .refused(let error) = uploads[attachment] { return error }
        return nil
    }

    private func runUploads() async {
        var failures = 0
        while !Task.isCancelled {
            guard let attachment = uploadQueue.first else {
                await nap(until: .upload)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .upload])
                continue
            }
            do {
                let result = try await client.upload(
                    attachment.id, name: attachment.name, mediaType: attachment.mediaType,
                    bytes: attachment.bytes)
                uploads[attachment.id] = .uploaded(result.attachment)
                // Its bytes stay until its message is accepted, in case the upload expires first.
                finishUpload(attachment.id, keepingBytes: true)
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.sendDelay(after: failures, error), until: [.network, .upload])
                } else if error.status == 401 {
                    problem = .tokenRejected(nil)
                    await nap(until: .upload)
                } else {
                    uploads[attachment.id] = .refused(error)
                    finishUpload(attachment.id, keepingBytes: false)
                }
            }
        }
    }

    private func finishUpload(_ attachment: AttachmentID, keepingBytes: Bool) {
        uploadQueue.removeAll { $0.id == attachment }
        if !keepingBytes { outbox.removeAttachment(attachment) }
        wake(.upload)
    }

    private func runStops() async {
        await runLane(.stop) {
            stopRequest?.turn
        } send: { turn throws(RequestError) in
            let result = try await client.stop(turn)
            updateEach { $0.confirm(result) }
        } done: { turn in
            if stopRequest?.turn == turn { stopRequest = nil }
        }
    }

    private func runRetries() async {
        await runLane(.retry) {
            retries.first
        } send: { turn throws(RequestError) in
            let result = try await client.retry(turn)
            updateEach { $0.confirm(result) }
        } done: { turn in
            if retries.first == turn { retries.removeFirst() }
        }
    }

    private func runCancels() async {
        await runLane(.cancel) {
            cancels.first
        } send: { ask throws(RequestError) in
            let result = try await client.cancelAsk(ask)
            if let thread = result.ask.thread {
                threadConversations[thread]?.confirm(result)
            } else {
                conversation.confirm(result)
            }
        } done: { ask in
            if cancels.first == ask { cancels.removeFirst() }
        }
    }

    /// Calls start and end in the order you asked.
    private func runCalls() async {
        await runLane(.call) {
            callRequests.first
        } send: { request throws(RequestError) in
            let result =
                switch request {
                case .start(let call): try await client.startCall(call)
                case .end(let call): try await client.endCall(call)
                case .deleteAudio(let call): try await client.deleteAudio(of: call)
                }
            conversation.confirm(result)
        } done: { request in
            if callRequests.first == request { callRequests.removeFirst() }
        }
    }

    /// Only the latest registration goes: one that came while an earlier one went is still to send.
    private func runDevice() async {
        await runLane(.device) {
            deviceRequest
        } send: { request throws(RequestError) in
            if let registration = request.registration {
                _ = try await client.registerDevice(request.id, registration)
            } else {
                try await client.removeDevice(request.id)
            }
        } done: { request in
            if deviceRequest?.id == request.id, deviceRequest?.registration == request.registration
            {
                deviceRequest = nil
            }
        }
    }

    private func runWhereabouts() async {
        await runLane(.whereabouts) {
            whereaboutsRequest
        } send: { request throws(RequestError) in
            try await client.setWhereabouts(request.device, request.whereabouts)
        } done: { request in
            if whereaboutsRequest?.whereabouts == request.whereabouts { whereaboutsRequest = nil }
        }
    }

    /// Sends a lane's requests one at a time: each goes when there's a network, again after a short
    /// wait if it failed for a passing reason, and leaves once the server has it or refuses it.
    private func runLane<Request>(
        _ wake: Wake, next: () -> Request?, send: (Request) async throws(RequestError) -> Void,
        done: (Request) -> Void
    ) async {
        var failures = 0
        while !Task.isCancelled {
            guard let request = next() else {
                await nap(until: wake)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, wake])
                continue
            }
            do throws(RequestError) {
                try await send(request)
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(
                        Self.commandDelay(after: failures, error), until: [.network, .live, wake])
                    continue
                }
            }
            done(request)
        }
    }

    // MARK: - Waiting

    /// What a lane waits for, so it can be woken early when it changes.
    struct Wake: OptionSet {
        let rawValue: Int
        static let network = Wake(rawValue: 1 << 0)
        static let live = Wake(rawValue: 1 << 1)
        static let outbox = Wake(rawValue: 1 << 2)
        static let stop = Wake(rawValue: 1 << 3)
        static let retry = Wake(rawValue: 1 << 4)
        static let cancel = Wake(rawValue: 1 << 5)
        static let device = Wake(rawValue: 1 << 6)
        static let whereabouts = Wake(rawValue: 1 << 7)
        static let upload = Wake(rawValue: 1 << 8)
        static let call = Wake(rawValue: 1 << 9)
    }

    /// A call to start, end, or delete the audio of, in the order you asked.
    enum CallRequest: Equatable {
        case start(CallID)
        case end(CallID)
        case deleteAudio(CallID)
    }

    /// Waits for `duration`, or, without one, until woken; anything in `reasons` wakes it early.
    private func nap(_ duration: Duration? = nil, until reasons: Wake) async {
        let id = nextSleeper
        nextSleeper += 1
        let ticker = ticker
        let task = Task { _ = try? await ticker.sleep(duration ?? .seconds(10 * 365 * 24 * 3600)) }
        sleepers[id] = (reasons: reasons, task: task)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        sleepers[id] = nil
    }

    private func wake(_ reason: Wake) {
        for sleeper in sleepers.values where !sleeper.reasons.isDisjoint(with: reason) {
            sleeper.task.cancel()
        }
    }

    /// No event and no ping for this long means the connection is gone. The server pings at least
    /// every 15 seconds.
    nonisolated static let silenceLimit = Duration.seconds(45)

    /// Before reconnecting the stream: half a second, doubling to 30. The network's return skips the
    /// wait.
    nonisolated static func reconnectDelay(after failures: Int) -> Duration {
        doubling(from: 500, upTo: 30_000, after: failures)
    }

    /// Before sending a message again: two seconds, doubling to 30, or as long as the server asked.
    nonisolated static func sendDelay(after failures: Int, _ error: RequestError) -> Duration {
        error.retryAfter ?? doubling(from: 2_000, upTo: 30_000, after: failures)
    }

    /// Before resending a Stop or Try again: half a second, doubling to 8, or as long as the server
    /// asked. They're what you're waiting on, so they retry sooner than messages.
    nonisolated static func commandDelay(after failures: Int, _ error: RequestError) -> Duration {
        error.retryAfter ?? doubling(from: 500, upTo: 8_000, after: failures)
    }

    /// `first` milliseconds after the first failure, doubling with each one after, up to `limit`.
    nonisolated private static func doubling(from first: Int, upTo limit: Int, after failures: Int)
        -> Duration
    {
        var milliseconds = first
        for _ in 1..<max(failures, 1) where milliseconds < limit { milliseconds *= 2 }
        return .milliseconds(min(milliseconds, limit))
    }
}

/// A clock opened once, so the session can sleep and read the time without knowing its type.
struct Ticker: Sendable {
    let sleep: @Sendable (Duration) async throws -> Void
    /// The time since the ticker was made.
    let now: @Sendable () -> Duration

    init<C: Clock>(_ clock: C) where C.Duration == Duration {
        let start = clock.now
        sleep = { try await clock.sleep(for: $0) }
        now = { start.duration(to: clock.now) }
    }
}
