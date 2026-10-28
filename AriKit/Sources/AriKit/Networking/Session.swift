import Foundation
import Observation

/// Ari's live connection to one server: the conversation, kept up to date from the event stream,
/// and everything you ask of it. SwiftUI watches it directly; the waiting (for the network, the
/// server, a retry) happens in small lanes that hand their results back here.
///
/// - The **event stream** resumes from the last event applied, reconnects with backoff, and treats
///   45 seconds without even a ping as a lost connection.
/// - The **outbox** saves each message on the device first, then sends one at a time, in order,
///   once the stream is live, retrying with the same id until the server has it.
/// - **Stop** has its own lane: never behind the outbox or a reconnect.
/// - **Try again** has its own lane too; the failed turn's id makes repeats safe.
/// - **Cancelling an ask** (Stop while it waits) has its own lane as well, and repeats are safe.
///   A secret answer goes from memory only, never through the outbox on disk.
/// - **Calls** start and end on their own lane, in order. A spoken message waits for its call's
///   start, and the end waits for the call's spoken messages, so none arrives after it.
@MainActor
@Observable
public final class Session {
    /// The conversation as Ari shows it.
    public private(set) var conversation: Conversation
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

    public enum Problem: Equatable, Sendable {
        /// The server stopped accepting the token.
        case tokenRejected(ServerError?)
        /// The server now speaks a protocol version this Ari doesn't.
        case protocolMismatch(ProtocolMismatch)
    }

    /// The longest message the server takes, in characters.
    public static let maximumLength = 32_000

    @ObservationIgnored private let client: ItoClient
    @ObservationIgnored private let outbox: OutboxStore
    @ObservationIgnored private let network: any NetworkPath
    @ObservationIgnored private let ticker: Ticker
    @ObservationIgnored private var queue: [SendMessage] = []
    @ObservationIgnored private var stopRequest: (turn: TurnID?, cut: Cut?)?
    @ObservationIgnored private var retries: [TurnID] = []
    @ObservationIgnored private var cancels: [AskID] = []
    @ObservationIgnored private var callRequests: [CallRequest] = []
    /// The device to register for notifications (or forget, with no registration), until the
    /// server has it.
    @ObservationIgnored private var deviceRequest: (id: String, registration: RegisterDevice?)?
    /// Whether the conversation is on screen here, as the server should next hear it.
    @ObservationIgnored private var presenceRequest: (device: String, looking: Bool)?
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
    /// Secret answers waiting to go: kept in memory only, never in the outbox on disk.
    @ObservationIgnored private var secrets: Set<MessageID> = []
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

    /// - Parameters:
    ///   - conversation: Where to start: the cached conversation, or an empty one.
    ///   - outbox: Where waiting messages are saved. Messages left from an earlier run are sent
    ///     after ``start()``.
    ///   - cache: Where attachments' bytes are kept once fetched or attached; with none, they're
    ///     fetched each time.
    public init(
        connection: Connection, conversation: Conversation = Conversation(), outbox: OutboxStore,
        cache: AttachmentCache? = nil, transport: any Transport = URLSessionTransport(),
        network: any NetworkPath = SystemNetworkPath(),
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.conversation = conversation
        self.address = connection.address
        self.outbox = outbox
        self.cache = cache
        self.network = network
        ticker = Ticker(clock)
        client = ItoClient(
            address: connection.address, token: connection.token, transport: transport)
    }

    // MARK: - Lifecycle

    /// Ari is on screen: connect, keep the stream live, and send whatever is waiting.
    public func start() {
        if lanes.isEmpty {
            let waiting = (try? outbox.load()) ?? []
            let named = Set(waiting.flatMap(\.uploads))
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
                    uploadQueue.first { $0.id == id }?.attachment
                }
                conversation.send(
                    message.id, text: message.text, attachments: waiting,
                    spoken: message.spoken.map { shown($0) })
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
                Task { await self.runPresence() },
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

    /// You tapped Send. Your message shows at once, is saved on the device, and goes as soon as it
    /// can. Returns its id, or `nil` if there's nothing to send or it's longer than the server takes.
    ///
    /// - Parameter id: Its permanent id and retry key; a new random UUID unless a test chooses one.
    /// While an ask waits, any message answers it.
    ///
    /// - Parameters:
    ///   - id: Its permanent id and retry key; a new random UUID unless a test chooses one.
    ///   - answers: The ask it answers, named when you tap one of its options or answer a secret.
    ///   - secret: A secret answer, such as a code: it goes from memory only, never saved on the
    ///     device, and the conversation keeps nothing of it.
    ///   - attachments: Photos and files attached with ``attach(_:)``. The message goes once
    ///     they're all on the server; the text may then be empty.
    ///   - spoken: For what you said on a call: the call, the recording attached with
    ///     ``attach(_:)``, and the words the phone corrected.
    @discardableResult
    public func send(
        _ text: String, id: MessageID = MessageID(UUID().uuidString.lowercased()),
        answers: AskID? = nil, secret: Bool = false, attachments: [AttachmentID] = [],
        spoken: SendSpoken? = nil
    ) -> MessageID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
            text.count <= Self.maximumLength
        else { return nil }
        let message = SendMessage(
            id: id, text: text, answers: answers, attachments: attachments, spoken: spoken)
        conversation.send(
            id, text: text, answers: answers, secret: secret,
            attachments: attachments.compactMap(attachment), spoken: spoken.map { shown($0) })
        if secret {
            secrets.insert(id)
        } else {
            try? outbox.add(message)
        }
        if !queue.contains(message) { queue.append(message) }
        wake(.outbox)
        return id
    }

    /// An attachment as the conversation shows it, once uploaded or while it waits to be.
    private func attachment(_ id: AttachmentID) -> Attachment? {
        if case .uploaded(let uploaded) = uploads[id] { return uploaded }
        return uploadQueue.first { $0.id == id }?.attachment
    }

    private func shown(_ spoken: SendSpoken) -> Spoken {
        Spoken(
            call: spoken.call, audio: spoken.audio.flatMap(attachment),
            corrections: spoken.corrections)
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

    /// You answered from a notification, with Ari closed or in the background: the message goes
    /// at once, without waiting for the event stream, and stays in the outbox until the server has
    /// it, so a failed attempt still goes next time Ari opens. Returns whether the server has it.
    @discardableResult
    public func sendFromNotification(
        _ text: String, id: MessageID = MessageID(UUID().uuidString.lowercased()),
        answers: AskID? = nil
    ) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= Self.maximumLength
        else { return false }
        let message = SendMessage(id: id, text: text, answers: answers)
        conversation.send(id, text: text, answers: answers)
        try? outbox.add(message)
        if !queue.contains(message) { queue.append(message) }
        do {
            let result = try await client.send(message)
            conversation.confirm(result)
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

    /// The conversation came on screen here, or left it. The server pushes nothing while any
    /// device is looking with a live stream; it forgets this when it restarts, so say it again
    /// after reconnecting.
    public func setLooking(_ looking: Bool, device: String) {
        presenceRequest = (device, looking)
        wake(.presence)
    }

    /// You started a call: it starts on the server as soon as it can, and spoken messages wait
    /// for it. Returns its id, for its spoken messages and its end.
    @discardableResult
    public func startCall(id: CallID = CallID(UUID().uuidString.lowercased())) -> CallID {
        callRequests.append(.start(id))
        wake(.call)
        return id
    }

    /// You ended the call: it ends once its spoken messages have gone.
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

    /// A call's stream to the server: your voice up, and Ari's voice and the call's state down.
    public func callStream(_ call: CallID) -> CallStream {
        let client = client
        return CallStream(connect: { client.callStream(call) })
    }

    /// You undid a correction or fixed a word: the server learns what was heard and what you
    /// meant. Returns whether it did.
    @discardableResult
    public func teach(_ pairs: [VocabularyCorrections.Pair]) async -> Bool {
        guard !pairs.isEmpty else { return true }
        return (try? await client.teach(VocabularyCorrections(corrections: pairs))) != nil
    }

    /// You tapped Stop while an ask waited: it settles at once, and the cancel goes on its own lane.
    public func cancel(_ ask: AskID) {
        guard conversation[ask: ask]?.outcome == nil, !cancels.contains(ask) else { return }
        conversation.cancel(ask)
        cancels.append(ask)
        wake(.cancel)
    }

    /// You tapped Stop. What's on screen holds there at once; the request goes on its own lane, even
    /// before the stream is back. Tapped before the turn is announced, it goes as soon as it is.
    ///
    /// The screen paces text, so it can still be showing a reply whose turn has already ended on
    /// the server. The Stop still goes, for the turn the cut message belongs to; the server answers
    /// that the turn had ended, and the rest of the reply shows.
    ///
    /// - Parameter cut: How much of the message being written was on screen.
    public func stop(cut: Cut?) {
        if let turn = cut.flatMap({ conversation[$0.message]?.turn }) ?? conversation.turn?.id {
            guard stopRequest?.turn != turn else { return }
            conversation.stop(turn: turn, cut: cut)
            stopRequest = (turn, cut)
        } else if conversation.entries.last?.role == .user {
            stopRequest = (nil, cut)
        } else {
            return
        }
        wake(.stop)
    }

    /// You tapped Try again on the failed `turn`. Tapping twice is safe: the server starts one
    /// attempt.
    public func tryAgain(_ turn: TurnID) {
        conversation.retry(turn: turn)
        retries.append(turn)
        wake(.retry)
    }

    /// You scrolled near the top: fetch the page of messages before the oldest Ari has.
    public func loadEarlier(limit: Int = 50) async {
        guard conversation.hasEarlierMessages, !isLoadingEarlier,
            let oldest = conversation.entries.first, oldest.delivery != .sending
        else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let page = try await client.messages(before: oldest.id, limit: limit)
            conversation.insertEarlier(page, before: oldest.id)
        } catch {
            // The server no longer has that message: Ari's view is stale, so replace it.
            if error.status == 404 {
                wantsSnapshot = true
                readingTask?.cancel()
            }
        }
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
        conversation.apply(event)
        if case .voiceStatus(let status) = event.payload { voiceStatus = status }
        switch event.payload {
        case .snapshot:
            wantsSnapshot = false
        case .turnStarted(let started):
            if let request = stopRequest, request.turn == nil {
                conversation.stop(turn: started.turn, cut: request.cut)
                stopRequest = (started.turn, request.cut)
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
            // A spoken message goes once its call has started.
            if let call = message.spoken?.call, callRequests.contains(.start(call)) {
                await nap(until: .call)
                continue
            }
            // A message goes once its attachments are on the server.
            let attached = message.uploads
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
                let result = try await client.send(message)
                conversation.confirm(result)
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
        let named = message.uploads
        let kept = outbox.attachments().filter { named.contains($0.id) }
        guard kept.count == named.count else { return false }
        for attachment in kept where !uploadQueue.contains(where: { $0.id == attachment.id }) {
            uploads[attachment.id] = .uploading
            uploadQueue.append(attachment)
        }
        wake(.upload)
        return true
    }

    /// The message went, or can't: it, and the bytes of its attachments, leave the outbox.
    private func finish(_ message: SendMessage) {
        queue.removeAll { $0.id == message.id }
        if secrets.remove(message.id) == nil { try? outbox.remove(message.id) }
        for attachment in message.uploads { outbox.removeAttachment(attachment) }
        wake(.outbox)
    }

    private func runStops() async {
        var failures = 0
        while !Task.isCancelled {
            guard let request = stopRequest, let turn = request.turn else {
                await nap(until: .stop)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .stop])
                continue
            }
            do {
                let result = try await client.stop(turn, cut: request.cut)
                conversation.confirm(result)
                if stopRequest?.turn == turn { stopRequest = nil }
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.commandDelay(after: failures, error), until: [.network, .live])
                } else {
                    if stopRequest?.turn == turn { stopRequest = nil }
                }
            }
        }
    }

    private func runRetries() async {
        var failures = 0
        while !Task.isCancelled {
            guard let turn = retries.first else {
                await nap(until: .retry)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .retry])
                continue
            }
            do {
                let result = try await client.retry(turn)
                conversation.confirm(result)
                retries.removeFirst()
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.commandDelay(after: failures, error), until: [.network, .live])
                } else {
                    retries.removeFirst()
                }
            }
        }
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

    private func runCancels() async {
        var failures = 0
        while !Task.isCancelled {
            guard let ask = cancels.first else {
                await nap(until: .cancel)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .cancel])
                continue
            }
            do {
                let result = try await client.cancelAsk(ask)
                conversation.confirm(result)
                cancels.removeFirst()
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.commandDelay(after: failures, error), until: [.network, .live])
                } else {
                    cancels.removeFirst()
                }
            }
        }
    }

    private func runCalls() async {
        var failures = 0
        while !Task.isCancelled {
            guard let request = callRequests.first else {
                await nap(until: .call)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .call])
                continue
            }
            // A call ends after its spoken messages have gone.
            if case .end(let call) = request, queue.contains(where: { $0.spoken?.call == call }) {
                await nap(until: .outbox)
                continue
            }
            do {
                let result =
                    switch request {
                    case .start(let call): try await client.startCall(call)
                    case .end(let call): try await client.endCall(call)
                    case .deleteAudio(let call): try await client.deleteAudio(of: call)
                    }
                conversation.confirm(result)
                callRequests.removeFirst()
                failures = 0
                wake(.call)
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(Self.commandDelay(after: failures, error), until: [.network, .live])
                } else {
                    callRequests.removeFirst()
                    wake(.call)
                }
            }
        }
    }

    private func runDevice() async {
        var failures = 0
        while !Task.isCancelled {
            guard let request = deviceRequest else {
                await nap(until: .device)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .device])
                continue
            }
            do {
                if let registration = request.registration {
                    _ = try await client.registerDevice(request.id, registration)
                } else {
                    try await client.removeDevice(request.id)
                }
                // A newer request that came while this one went is still to send.
                if deviceRequest?.id == request.id,
                    deviceRequest?.registration == request.registration
                {
                    deviceRequest = nil
                }
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(
                        Self.commandDelay(after: failures, error), until: [.network, .device])
                } else {
                    deviceRequest = nil
                }
            }
        }
    }

    private func runPresence() async {
        var failures = 0
        while !Task.isCancelled {
            guard let request = presenceRequest else {
                await nap(until: .presence)
                continue
            }
            guard isOnline else {
                await nap(until: [.network, .presence])
                continue
            }
            do {
                try await client.setPresence(request.device, looking: request.looking)
                if presenceRequest?.looking == request.looking { presenceRequest = nil }
                failures = 0
            } catch {
                if error.isTemporary {
                    failures += 1
                    await nap(
                        Self.commandDelay(after: failures, error), until: [.network, .presence])
                } else {
                    presenceRequest = nil
                }
            }
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
        static let presence = Wake(rawValue: 1 << 7)
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
