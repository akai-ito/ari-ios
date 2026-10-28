/// One event from `GET /v0/events`. It decodes envelope first: its id and type, then the fields of a
/// type this version of Ari knows. A type it doesn't know decodes as ``Payload/unknown`` and keeps its
/// id, so the cursor still moves past it; fields Ari doesn't know are ignored.
public struct Event: Sendable, Equatable, Decodable {
    /// The cursor to resume from. Only a snapshot of an empty conversation has none.
    public let id: EventID?
    /// The type, as sent.
    public let type: String
    public let payload: Payload

    public enum Payload: Sendable, Equatable {
        case snapshot(Snapshot)
        case messageAccepted(MessageAccepted)
        case messageQueued(MessageQueued)
        case messageRead(MessageRead)
        case turnStarted(TurnStarted)
        case turnStatus(TurnStatus)
        case stepStarted(StepEvent)
        case stepUpdated(StepEvent)
        case stepEnded(StepEvent)
        case askStarted(AskEvent)
        case askEnded(AskEvent)
        case messageStarted(MessageStarted)
        case messageDelta(MessageDelta)
        case messageEnded(MessageEnded)
        case turnEnded(TurnEnded)
        case callStarted(CallEvent)
        case callEnded(CallEvent)
        case callAudioDeleted(CallEvent)
        case voiceStatus(VoiceStatus)
        /// A type this version of Ari doesn't know: skip it, but keep its id as the cursor.
        case unknown
    }

    /// Every type this version of Ari decodes, as named on the wire.
    public static let knownTypes = [
        "snapshot", "message.accepted", "message.queued", "message.read", "turn.started",
        "turn.status", "step.started", "step.updated", "step.ended", "ask.started", "ask.ended",
        "message.started", "message.delta", "message.ended", "turn.ended", "call.started",
        "call.ended", "call.audio_deleted", "voice.status",
    ]

    private enum EnvelopeKeys: String, CodingKey {
        case id, type
    }

    public init(from decoder: any Decoder) throws {
        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)
        id = try envelope.decodeIfPresent(EventID.self, forKey: .id)
        type = try envelope.decode(String.self, forKey: .type)
        payload =
            switch type {
            case "snapshot": .snapshot(try Snapshot(from: decoder))
            case "message.accepted": .messageAccepted(try MessageAccepted(from: decoder))
            case "message.queued": .messageQueued(try MessageQueued(from: decoder))
            case "message.read": .messageRead(try MessageRead(from: decoder))
            case "turn.started": .turnStarted(try TurnStarted(from: decoder))
            case "turn.status": .turnStatus(try TurnStatus(from: decoder))
            case "step.started": .stepStarted(try StepEvent(from: decoder))
            case "step.updated": .stepUpdated(try StepEvent(from: decoder))
            case "step.ended": .stepEnded(try StepEvent(from: decoder))
            case "ask.started": .askStarted(try AskEvent(from: decoder))
            case "ask.ended": .askEnded(try AskEvent(from: decoder))
            case "message.started": .messageStarted(try MessageStarted(from: decoder))
            case "message.delta": .messageDelta(try MessageDelta(from: decoder))
            case "message.ended": .messageEnded(try MessageEnded(from: decoder))
            case "turn.ended": .turnEnded(try TurnEnded(from: decoder))
            case "call.started": .callStarted(try CallEvent(from: decoder))
            case "call.ended": .callEnded(try CallEvent(from: decoder))
            case "call.audio_deleted": .callAudioDeleted(try CallEvent(from: decoder))
            case "voice.status": .voiceStatus(try VoiceStatus(from: decoder))
            default: .unknown
            }
    }
}

/// Sent first when the server can't resume from the cursor (there was none, the server doesn't know
/// it, or it is too far behind): replace the conversation with it. Its id repeats the latest event's.
public struct Snapshot: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let reason: SnapshotReason
    /// The latest messages, oldest first, including one still being written.
    public let messages: [Message]
    /// Every step from the first of those messages on, the running turn's included, in position
    /// order.
    public let steps: [Step]
    /// Every ask from the first of those messages on, the one waiting for your answer included.
    public let asks: [Ask]
    /// The calls that started within those messages, and one still on.
    public let calls: [Call]
    /// Whether older messages exist.
    public let hasMore: Bool
    /// The running turn, or `nil` when the agent is idle.
    public let turn: LiveTurn?
    /// Messages waiting as Next, in the order they will be answered.
    public let next: [MessageID]

    enum CodingKeys: String, CodingKey {
        case at, reason, messages, steps, asks, calls, turn, next
        case hasMore = "has_more"
    }
}

/// A message you sent is on the server's disk. Every connected app receives it, the sender included.
public struct MessageAccepted: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: Message
}

/// The message can't join the running turn, so it waits as Next.
public struct MessageQueued: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: MessageID
    /// The running turn it waits behind.
    public let turn: TurnID
}

/// The agent took the message into the running turn. A reply it was already writing may finish
/// first.
public struct MessageRead: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: MessageID
    public let turn: TurnID
}

/// The agent starts working; Stop works from here.
public struct TurnStarted: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let turn: TurnID
    /// The messages this turn answers, in the order they were sent.
    public let inputs: [MessageID]
    /// Present when this is a new attempt at a failed turn.
    public let retryOf: TurnID?

    enum CodingKeys: String, CodingKey {
        case at, turn, inputs
        case retryOf = "retry_of"
    }
}

/// What the agent is doing now. It replaces the previous status; `turn.ended` clears it.
public struct TurnStatus: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let turn: TurnID
    public let kind: StatusKind
    public let label: String
    public let detail: String?

    public var status: Status { Status(kind: kind, label: label, detail: detail) }
}

/// A step starts (its title in the present tense), more is known about it, or it ends (with its
/// outcome, duration and past-tense title). Each carries the whole step as it now stands.
public struct StepEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let step: Step
}

/// The agent asks you something (and its turn ends next), or the ask is settled: answered by a
/// message, which `message.accepted` brings first, or cancelled. Each carries the whole ask.
public struct AskEvent: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let ask: Ask
}

/// The agent begins a message, with empty text and no outcome; `message.delta` events follow.
public struct MessageStarted: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: Message
}

/// Text appended to a message. Text is never revised: `offset` is always the message's length before
/// this piece.
public struct MessageDelta: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: MessageID
    /// Where the piece starts, in UTF-16 code units.
    public let offset: Int
    public let text: String
}

/// A message is finished. Its final text is its first `length` UTF-16 code units: everything
/// streamed, or less when you stopped it.
public struct MessageEnded: Sendable, Equatable, Decodable {
    /// When it ended: the message's `ended_at`.
    public let at: Timestamp
    public let message: MessageID
    public let outcome: Outcome
    /// The final length of the text, in UTF-16 code units.
    public let length: Int
    public let error: ServerError?
}

/// The turn is over and its status is cleared. Nothing more about this turn follows.
public struct TurnEnded: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let turn: TurnID
    public let outcome: Outcome
    public let error: ServerError?
}
