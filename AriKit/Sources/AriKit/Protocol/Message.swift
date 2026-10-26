/// One message in the conversation, as snapshots, history pages and command answers carry it.
/// Messages are ordered by when they began.
public struct Message: Hashable, Sendable, Codable {
    public var id: MessageID
    public var role: Role
    /// Agent messages only: a reply, or a note while the agent works.
    public var kind: MessageKind?
    /// Agent messages only: the turn that wrote it.
    public var turn: TurnID?
    /// GitHub-flavoured Markdown, exactly as written; while the message is still being written, the
    /// text so far.
    public var text: String
    /// When it began: when the server accepted it, or the agent's first word.
    public var at: Timestamp
    /// Where it sits in the conversation, in one order with the agent's steps. The protocol always
    /// sends it.
    public var position: Int?
    /// Agent messages only: when it ended.
    public var endedAt: Timestamp?
    /// Agent messages only; absent while the message is still being written.
    public var outcome: Outcome?
    /// Present when the outcome is failed.
    public var error: ServerError?
    /// Your messages only: the ask this message answered.
    public var answers: AskID?
    /// Your messages only: a secret answer, such as a code. Its text is always empty: the agent
    /// received what you typed, and the conversation keeps nothing of it.
    public var secret: Bool?
    /// Your messages only: the photos and files you attached, in order.
    public var attachments: [Attachment]?
    /// Your messages only: how a message you spoke on a call came to be.
    public var spoken: Spoken?

    public init(
        id: MessageID, role: Role, kind: MessageKind? = nil, turn: TurnID? = nil, text: String,
        at: Timestamp, position: Int? = nil, endedAt: Timestamp? = nil, outcome: Outcome? = nil,
        error: ServerError? = nil
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.turn = turn
        self.text = text
        self.at = at
        self.position = position
        self.endedAt = endedAt
        self.outcome = outcome
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id, role, kind, turn, text, at, position, outcome, error, answers, secret, attachments,
            spoken
        case endedAt = "ended_at"
    }
}

/// What the agent is doing right now.
public struct Status: Hashable, Sendable, Codable {
    /// Coarse, for animating the agent's presence.
    public var kind: StatusKind
    /// Plain words to show, such as "Searching the web".
    public var label: String
    /// Optional plain-word specifics, such as a search query.
    public var detail: String?

    public init(kind: StatusKind, label: String, detail: String? = nil) {
        self.kind = kind
        self.label = label
        self.detail = detail
    }
}

/// The turn that was running when a snapshot was taken.
public struct LiveTurn: Hashable, Sendable, Codable {
    public var id: TurnID
    /// The messages the turn started with.
    public var inputs: [MessageID]
    /// Messages sent while it ran that the agent has since taken in.
    public var read: [MessageID]
    /// Present when the turn is a new attempt at a failed one.
    public var retryOf: TurnID?
    /// The live status, if there is one yet.
    public var status: Status?

    enum CodingKeys: String, CodingKey {
        case id, inputs, read, status
        case retryOf = "retry_of"
    }
}

/// Why something failed: a stable code, a plain sentence written by the server for the person using
/// the app, and the technical cause for a Details view.
public struct ServerError: Error, Hashable, Sendable, Codable {
    public var code: ErrorCode
    public var message: String
    /// The protocol doesn't require it, so Details may have nothing to show.
    public var detail: String?

    public init(code: ErrorCode, message: String, detail: String? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
    }
}
