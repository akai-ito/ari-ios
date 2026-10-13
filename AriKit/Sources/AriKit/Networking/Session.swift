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
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private var wantsSnapshot = false
    @ObservationIgnored private var lastHeard: Duration = .zero
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var readingTask: Task<Void, any Error>?
    @ObservationIgnored private var lanes: [Task<Void, Never>] = []
    @ObservationIgnored private var sleepers: [Int: (reasons: Wake, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var nextSleeper = 0

    /// - Parameters:
    ///   - conversation: Where to start: the cached conversation, or an empty one.
    ///   - outbox: Where waiting messages are saved. Messages left from an earlier run are sent
    ///     after ``start()``.
    public init(
        connection: Connection, conversation: Conversation = Conversation(), outbox: OutboxStore,
        transport: any Transport = URLSessionTransport(),
        network: any NetworkPath = SystemNetworkPath(),
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.conversation = conversation
        self.outbox = outbox
        self.network = network
        ticker = Ticker(clock)
        client = ItoClient(
            address: connection.address, token: connection.token, transport: transport)
    }

    // MARK: - Lifecycle

    /// Ari is on screen: connect, keep the stream live, and send whatever is waiting.
    public func start() {
        if lanes.isEmpty {
            for message in (try? outbox.load()) ?? [] where !queue.contains(message) {
                conversation.send(message.id, text: message.text)
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
    @discardableResult
    public func send(_ text: String, id: MessageID = MessageID(UUID().uuidString.lowercased()))
        -> MessageID?
    {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= Self.maximumLength
        else { return nil }
        let message = SendMessage(id: id, text: text)
        conversation.send(id, text: text)
        try? outbox.add(message)
        if !queue.contains(message) { queue.append(message) }
        wake(.outbox)
        return id
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
                } else {
                    refusedMessages[message.id] = error
                    finish(message)
                }
            }
        }
    }

    private func finish(_ message: SendMessage) {
        queue.removeAll { $0.id == message.id }
        try? outbox.remove(message.id)
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

    // MARK: - Waiting

    /// What a lane waits for, so it can be woken early when it changes.
    struct Wake: OptionSet {
        let rawValue: Int
        static let network = Wake(rawValue: 1 << 0)
        static let live = Wake(rawValue: 1 << 1)
        static let outbox = Wake(rawValue: 1 << 2)
        static let stop = Wake(rawValue: 1 << 3)
        static let retry = Wake(rawValue: 1 << 4)
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
