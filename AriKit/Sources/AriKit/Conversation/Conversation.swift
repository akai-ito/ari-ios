/// The conversation as Ari shows it. All of it comes from the server: its events, applied in order,
/// and its answers to what Ari asks. Ari changes it ahead of the server only for what you do (your
/// message the moment you send it, Stop's freeze, and Try again), and the server then confirms each.
public struct Conversation: Sendable, Equatable {
    /// The last event applied: send it as `Last-Event-ID` to resume. `nil` before the first event,
    /// after a snapshot of an empty conversation, and when the view needs a snapshot.
    public private(set) var cursor: EventID?
    /// Whether an event broke a rule the server promises, such as a gap in a message's text. Nothing
    /// more is applied until a snapshot arrives: reconnect without a cursor to get one.
    public private(set) var needsSnapshot = false
    /// The messages, oldest first: the server's order, then your messages it hasn't accepted yet, in
    /// the order you sent them.
    public private(set) var entries: [Entry] = []
    /// Whether older messages exist on the server, to page back to.
    public private(set) var hasEarlierMessages = false
    /// The turn the agent is working on, if any.
    public private(set) var turn: Turn?
    /// The latest turn that ended, until another starts: for a moment of Stopped, Couldn't finish or
    /// Interrupted.
    public private(set) var lastEndedTurn: EndedTurn?
    /// Your Stop, from the tap until its turn ends.
    public private(set) var pendingStop: StopRequest?
    /// Failed turns already tried again, so Try again shows only once.
    public private(set) var retriedTurns: Set<TurnID> = []

    /// Each entry's index in `entries`.
    private var positions: [MessageID: Int] = [:]
    /// How many entries, from the start, the server has put in its order. The rest are yours, still on
    /// their way.
    private var serverCount = 0

    public init() {}
}

extension Conversation {
    /// A message as the conversation shows it.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: MessageID
        public internal(set) var role: Role
        public internal(set) var kind: MessageKind?
        public internal(set) var turn: TurnID?
        /// Everything received so far; once the message ends, exactly its first `length` UTF-16 units.
        public internal(set) var text: String
        /// The text's length in UTF-16 code units, the unit of offsets, lengths and cuts.
        public internal(set) var length: Int
        /// When it began, by the server's clock; `nil` while your message is only on this device.
        public internal(set) var at: Timestamp?
        public internal(set) var endedAt: Timestamp?
        /// How the agent's message ended; `nil` while it's being written.
        public internal(set) var outcome: Outcome?
        public internal(set) var error: ServerError?
        /// Your messages: whether the server has it yet.
        public internal(set) var delivery: Delivery?
        /// Your messages: taken into the running turn, or waiting for the next one.
        public internal(set) var mark: Mark?

        public enum Delivery: Sendable, Equatable {
            /// Saved on this device; the server hasn't confirmed it.
            case sending
            /// On the server's disk.
            case delivered
        }

        public enum Mark: Sendable, Equatable {
            /// The agent took it into the running turn.
            case read
            /// It waits for the turn after this one.
            case next
        }

        /// Whether the conversation shows it: your messages and the agent's replies. A note becomes the
        /// live status's detail instead, and a role or kind this version of Ari doesn't know stays hidden.
        public var isShown: Bool { role == .user || (role == .agent && kind == .reply) }

        init(_ message: Message) {
            id = message.id
            role = message.role
            kind = message.kind
            turn = message.turn
            text = message.text
            length = message.text.utf16.count
            at = message.at
            endedAt = message.endedAt
            outcome = message.outcome
            error = message.error
            delivery = message.role == .user ? .delivered : nil
        }

        init(sending id: MessageID, text: String) {
            self.id = id
            role = .user
            self.text = text
            length = text.utf16.count
            delivery = .sending
        }
    }

    /// A turn the agent is working on.
    public struct Turn: Sendable, Equatable {
        public let id: TurnID
        /// The messages it answers.
        public var inputs: [MessageID]
        public var retryOf: TurnID?
        /// What the agent is doing now, in plain words; `nil` until the first status.
        public var status: Status?
    }

    /// How a turn ended.
    public struct EndedTurn: Sendable, Equatable {
        public let id: TurnID
        public let outcome: Outcome
        public let error: ServerError?
    }

    /// Your Stop. Until its turn ends, the message it cut holds at the cut.
    public struct StopRequest: Sendable, Equatable {
        public let turn: TurnID
        public let cut: Cut?
    }
}

// MARK: - The server's events

extension Conversation {
    /// Applies the next event from the stream. Events come in the stream's order, each exactly once,
    /// as the server guarantees from a cursor. One that can't be (a gap in a message's text, a piece of
    /// a message that never began) changes nothing and sets ``needsSnapshot``.
    public mutating func apply(_ event: Event) {
        if case .snapshot(let snapshot) = event.payload {
            replace(with: snapshot, cursor: event.id)
            return
        }
        guard !needsSnapshot else { return }

        var applied = true
        switch event.payload {
        case .snapshot:
            return
        case .messageAccepted(let accepted):
            accept(accepted.message)
        case .messageQueued(let queued):
            mark(queued.message, .next)
        case .messageRead(let read):
            if read.turn == turn?.id { mark(read.message, .read) }
        case .turnStarted(let started):
            start(started)
        case .turnStatus(let update):
            // A status replaces the last one completely, and only the running turn has one.
            if update.turn == turn?.id { turn?.status = update.status }
        case .messageStarted(let started):
            begin(started.message)
        case .messageDelta(let delta):
            applied = append(delta)
        case .messageEnded(let ended):
            applied = end(ended)
        case .turnEnded(let ended):
            finish(ended)
        case .unknown:
            break
        }

        if !applied {
            needsSnapshot = true
            cursor = nil
        } else if let id = event.id {
            cursor = id
        }
    }

    private mutating func replace(with snapshot: Snapshot, cursor id: EventID?) {
        let included = Set(snapshot.messages.map(\.id))
        // Your messages that aren't in the snapshot stay below it: those the server hasn't confirmed
        // are still on their way, and one it confirmed after taking the snapshot is placed by its
        // `message.accepted`, which follows.
        let waiting = entries[serverCount...].filter { !included.contains($0.id) }
        entries = snapshot.messages.map(Entry.init) + waiting
        serverCount = snapshot.messages.count
        positions = [:]
        reindex(from: 0)

        hasEarlierMessages = snapshot.hasMore
        turn = snapshot.turn.map {
            Turn(id: $0.id, inputs: $0.inputs, retryOf: $0.retryOf, status: $0.status)
        }
        for id in snapshot.turn?.read ?? [] { mark(id, .read) }
        for id in snapshot.next { mark(id, .next) }
        if let retried = snapshot.turn?.retryOf { retriedTurns.insert(retried) }
        lastEndedTurn = nil
        if pendingStop?.turn != turn?.id { pendingStop = nil }
        needsSnapshot = false
        cursor = id
    }

    private mutating func accept(_ message: Message) {
        guard let index = positions[message.id] else {
            insert(Entry(message), at: serverCount)
            serverCount += 1
            return
        }
        var entry = Entry(message)
        entry.mark = entries[index].mark
        if index < serverCount {
            entries[index] = entry
            return
        }
        // Yours waited below the server's messages; now it takes its place in the server's order.
        entries.remove(at: index)
        entries.insert(entry, at: serverCount)
        reindex(from: serverCount)
        serverCount += 1
    }

    private mutating func begin(_ message: Message) {
        guard positions[message.id] == nil else { return }
        insert(Entry(message), at: serverCount)
        serverCount += 1
    }

    private mutating func append(_ delta: MessageDelta) -> Bool {
        guard let index = positions[delta.message] else { return false }
        let length = entries[index].length
        let pieceLength = delta.text.utf16.count
        if delta.offset == length, entries[index].outcome == nil {
            entries[index].text.append(delta.text)
            entries[index].length += pieceLength
            return true
        }
        // A piece already here, word for word, changes nothing; any other offset means text was lost
        // or would be revised.
        guard delta.offset >= 0, delta.offset <= length - pieceLength else { return false }
        let units = entries[index].text.utf16
        let start = units.index(units.startIndex, offsetBy: delta.offset)
        let end = units.index(start, offsetBy: pieceLength)
        return units[start..<end].elementsEqual(delta.text.utf16)
    }

    private mutating func end(_ ended: MessageEnded) -> Bool {
        guard let index = positions[ended.message],
            (0...entries[index].length).contains(ended.length)
        else { return false }
        if ended.length < entries[index].length {
            entries[index].text = entries[index].text.prefix(utf16: ended.length)
            entries[index].length = entries[index].text.utf16.count
        }
        entries[index].outcome = ended.outcome
        entries[index].error = ended.error
        entries[index].endedAt = ended.at
        return true
    }

    private mutating func start(_ started: TurnStarted) {
        turn = Turn(id: started.turn, inputs: started.inputs, retryOf: started.retryOf, status: nil)
        lastEndedTurn = nil
        if pendingStop?.turn != started.turn { pendingStop = nil }
        // The turn answers its inputs now, so none of them waits as Next any more.
        for input in started.inputs {
            if let index = positions[input] { entries[index].mark = nil }
        }
        if let retried = started.retryOf { retriedTurns.insert(retried) }
    }

    private mutating func finish(_ ended: TurnEnded) {
        if pendingStop?.turn == ended.turn { pendingStop = nil }
        guard turn?.id == ended.turn else { return }
        turn = nil
        lastEndedTurn = EndedTurn(id: ended.turn, outcome: ended.outcome, error: ended.error)
        for index in entries.indices {
            // Read belongs to the turn that took the message in.
            if entries[index].mark == .read { entries[index].mark = nil }
            // Nothing about a turn follows its end, so a message it left open has ended with it.
            if entries[index].turn == ended.turn, entries[index].role == .agent,
                entries[index].outcome == nil
            {
                entries[index].outcome = ended.outcome
                entries[index].error = ended.error
                entries[index].endedAt = ended.at
            }
        }
    }

    private mutating func mark(_ id: MessageID, _ mark: Entry.Mark) {
        guard let index = positions[id], entries[index].role == .user else { return }
        entries[index].mark = mark
    }
}

// MARK: - What you do, and the server's answers

extension Conversation {
    /// You tapped Send: your message shows at once, below everything the server has, until the server
    /// accepts it. `id` is its permanent id and its retry key; sending the same id again does nothing.
    public mutating func send(_ id: MessageID, text: String) {
        guard positions[id] == nil else { return }
        entries.append(Entry(sending: id, text: text))
        positions[id] = entries.count - 1
    }

    /// The server answered a send (201, or 200 for a repeat): it has your message, so Sending can go.
    /// The message keeps its place until `message.accepted` puts it in the server's order.
    public mutating func confirm(_ result: MessageResult) {
        guard let index = positions[result.message.id], entries[index].delivery == .sending else {
            return
        }
        entries[index].delivery = .delivered
        entries[index].at = result.message.at
    }

    /// You tapped Stop on `turn`. `cut` says how much of the message being written was on screen: it
    /// holds there (see ``visibleText(of:)``) until the turn ends. A Stop for a turn that has already
    /// ended changes nothing; the rest of its reply simply shows.
    public mutating func stop(turn id: TurnID, cut: Cut?) {
        guard turn?.id == id, pendingStop == nil else { return }
        pendingStop = StopRequest(turn: id, cut: cut)
    }

    /// The server answered a Stop. If the turn had already ended some other way (the reply finished
    /// first, say), nothing stays frozen: the reply shows in full, without a Stopped tag. If it ended
    /// stopped, by this Stop or another device's, the freeze holds until the stream brings the stopped
    /// message's length and the turn's end.
    public mutating func confirm(_ result: StopResult) {
        guard pendingStop?.turn == result.turn, result.state == .ended, result.outcome != .stopped
        else { return }
        pendingStop = nil
    }

    /// You tapped Try again on the failed `turn`.
    public mutating func retry(turn id: TurnID) {
        retriedTurns.insert(id)
    }

    /// The server answered Try again with the new attempt, which `turn.started` also announces.
    public mutating func confirm(_ result: RetryResult) {
        retriedTurns.insert(result.retryOf)
    }

    /// A page of older messages arrived, for a request made before `oldest`. A page that no longer fits,
    /// because the view was replaced since, is dropped.
    public mutating func insertEarlier(_ page: MessagePage, before oldest: MessageID) {
        guard serverCount > 0, entries[0].id == oldest else { return }
        let earlier = page.messages.filter { positions[$0.id] == nil }.map(Entry.init)
        insert(contentsOf: earlier, at: 0)
        serverCount += earlier.count
        hasEarlierMessages = page.hasMore
    }

    /// Forgets the messages before `id`, as a cache that keeps only recent history does. They can be
    /// paged back in.
    public mutating func forgetMessages(before id: MessageID) {
        guard let index = positions[id], index > 0, index < serverCount else { return }
        for entry in entries[..<index] { positions[entry.id] = nil }
        entries.removeFirst(index)
        serverCount -= index
        reindex(from: 0)
        hasEarlierMessages = true
    }
}

// MARK: - Reading it

extension Conversation {
    /// The most of `entry`'s text that may be on screen: everything received, except that while your
    /// Stop is pending, the message it cut holds at the cut.
    public func visibleText(of entry: Entry) -> String {
        guard let cut = pendingStop?.cut, cut.message == entry.id else { return entry.text }
        return entry.text.prefix(utf16: cut.offset)
    }

    /// The note the agent is writing right now, if any: its text is the live status's detail.
    public var noteInProgress: Entry? {
        guard let turn else { return nil }
        return entries.last { $0.turn == turn.id && $0.kind == .note && $0.outcome == nil }
    }

    /// The entry with `id`, if the conversation has it.
    public subscript(id: MessageID) -> Entry? {
        positions[id].map { entries[$0] }
    }
}

// MARK: - Bookkeeping

extension Conversation {
    private mutating func insert(_ entry: Entry, at index: Int) {
        insert(contentsOf: [entry], at: index)
    }

    private mutating func insert(contentsOf inserted: [Entry], at index: Int) {
        guard !inserted.isEmpty else { return }
        entries.insert(contentsOf: inserted, at: index)
        reindex(from: index)
    }

    private mutating func reindex(from start: Int) {
        for index in start..<entries.count { positions[entries[index].id] = index }
    }
}

extension String {
    /// The first `count` UTF-16 code units, rounded down to a whole Unicode scalar so that a surrogate
    /// pair is never split.
    func prefix(utf16 count: Int) -> String {
        guard count > 0 else { return "" }
        let units = utf16
        guard count < units.count else { return self }
        var end = units.index(units.startIndex, offsetBy: count)
        if end.samePosition(in: unicodeScalars) == nil { end = units.index(before: end) }
        return String(Substring(unicodeScalars[..<end]))
    }
}
