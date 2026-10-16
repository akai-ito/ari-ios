// The protocol's enumerations, kept open: a value this version of Ari doesn't know still decodes, keeps
// its text, and falls back as the protocol says. Each is a struct with a constant per known value, so
// a `switch` over one always needs a `default`.

/// A value from one of the protocol's open enumerations.
public protocol OpenValue: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
    /// Every value this version of Ari knows.
    static var known: [Self] { get }
}

extension OpenValue {
    /// Whether this version of Ari knows the value.
    public var isKnown: Bool { Self.known.contains(self) }
    public var description: String { rawValue }
}

/// Who wrote a message. Ari hides a role it doesn't know.
public struct Role: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// What you send.
    public static let user = Role(rawValue: "user")
    /// What the agent writes.
    public static let agent = Role(rawValue: "agent")
    public static let known = [user, agent]
}

/// The kind of an agent's message. Ari hides a kind it doesn't know.
public struct MessageKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Part of the answer.
    public static let reply = MessageKind(rawValue: "reply")
    /// The agent's commentary while it works, such as "I'll check current prices first."
    public static let note = MessageKind(rawValue: "note")
    public static let known = [reply, note]
}

/// How a message or a turn ended. An outcome Ari doesn't know means only that it ended.
public struct Outcome: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let completed = Outcome(rawValue: "completed")
    /// You stopped it.
    public static let stopped = Outcome(rawValue: "stopped")
    /// The server restarted while it ran.
    public static let interrupted = Outcome(rawValue: "interrupted")
    /// It failed, with an error.
    public static let failed = Outcome(rawValue: "failed")
    public static let known = [completed, stopped, interrupted, failed]
}

/// What the agent is doing, coarsely, for animating its presence. For a kind Ari doesn't know, the
/// status's label is still shown.
public struct StatusKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let thinking = StatusKind(rawValue: "thinking")
    public static let working = StatusKind(rawValue: "working")
    public static let writing = StatusKind(rawValue: "writing")
    public static let adjusting = StatusKind(rawValue: "adjusting")
    public static let waiting = StatusKind(rawValue: "waiting")
    public static let stopping = StatusKind(rawValue: "stopping")
    public static let known = [thinking, working, writing, adjusting, waiting, stopping]
}

/// Why the server sent a snapshot instead of resuming. Ari applies every snapshot the same way, so a
/// reason it doesn't know changes nothing.
public struct SnapshotReason: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let noCursor = SnapshotReason(rawValue: "no_cursor")
    public static let cursorUnknown = SnapshotReason(rawValue: "cursor_unknown")
    public static let tooFarBehind = SnapshotReason(rawValue: "too_far_behind")
    public static let known = [noCursor, cursorUnknown, tooFarBehind]
}

/// Where a turn stood when the server answered a Stop. A state Ari doesn't know means the server has
/// the Stop; `turn.ended` says what came of it.
public struct StopState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The agent is being stopped; `turn.ended` follows.
    public static let stopping = StopState(rawValue: "stopping")
    /// The turn had already ended; the answer says how.
    public static let ended = StopState(rawValue: "ended")
    public static let known = [stopping, ended]
}

/// Why something failed. Codes are added over time; for one Ari doesn't know, show the error's message.
public struct ErrorCode: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    // A failed turn.
    public static let modelTimeout = ErrorCode(rawValue: "model_timeout")
    public static let modelUnavailable = ErrorCode(rawValue: "model_unavailable")
    public static let usageLimit = ErrorCode(rawValue: "usage_limit")
    public static let engineSignedOut = ErrorCode(rawValue: "engine_signed_out")
    public static let contextFull = ErrorCode(rawValue: "context_full")
    public static let engineFailed = ErrorCode(rawValue: "engine_failed")
    public static let serverDiskFull = ErrorCode(rawValue: "server_disk_full")
    public static let refused = ErrorCode(rawValue: "refused")
    // A refused command.
    public static let invalidRequest = ErrorCode(rawValue: "invalid_request")
    public static let tokenRejected = ErrorCode(rawValue: "token_rejected")
    public static let pairingCodeRejected = ErrorCode(rawValue: "pairing_code_rejected")
    public static let notFound = ErrorCode(rawValue: "not_found")
    public static let idConflict = ErrorCode(rawValue: "id_conflict")
    public static let tooLarge = ErrorCode(rawValue: "too_large")
    /// A message names an attachment the server doesn't have, as when an upload waited more than a
    /// day for its message: upload it again, under the same id, and send again.
    public static let attachmentMissing = ErrorCode(rawValue: "attachment_missing")
    public static let slowDown = ErrorCode(rawValue: "slow_down")
    public static let unavailable = ErrorCode(rawValue: "unavailable")
    // Either.
    public static let `internal` = ErrorCode(rawValue: "internal")

    public static let known = [
        modelTimeout, modelUnavailable, usageLimit, engineSignedOut, contextFull, engineFailed,
        serverDiskFull, refused, invalidRequest, tokenRejected, pairingCodeRejected, notFound,
        idConflict, tooLarge, attachmentMissing,
        slowDown,
        unavailable, `internal`,
    ]
}

/// What kind of thing the agent did in a step. For a kind Ari doesn't know, the step's title is
/// still shown.
public struct StepKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let thinking = StepKind(rawValue: "thinking")
    public static let webSearch = StepKind(rawValue: "web_search")
    /// A command, and what it did as far as the engine could tell: read, search, list, run.
    public static let command = StepKind(rawValue: "command")
    public static let fileChange = StepKind(rawValue: "file_change")
    public static let tool = StepKind(rawValue: "tool")
    public static let plan = StepKind(rawValue: "plan")
    public static let wait = StepKind(rawValue: "wait")
    public static let imageView = StepKind(rawValue: "image_view")
    /// Tidying up its notes, so the conversation fits.
    public static let compacting = StepKind(rawValue: "compacting")
    public static let known = [
        thinking, webSearch, command, fileChange, tool, plan, wait, imageView, compacting,
    ]
}

/// What a command did, as far as the engine could tell. For one Ari doesn't know, treat it as run.
public struct ActionType: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let read = ActionType(rawValue: "read")
    public static let search = ActionType(rawValue: "search")
    public static let list = ActionType(rawValue: "list")
    public static let run = ActionType(rawValue: "run")
    public static let known = [read, search, list, run]
}

/// How a file changed. For one Ari doesn't know, treat it as modified.
public struct FileChangeKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let added = FileChangeKind(rawValue: "added")
    public static let modified = FileChangeKind(rawValue: "modified")
    public static let deleted = FileChangeKind(rawValue: "deleted")
    public static let moved = FileChangeKind(rawValue: "moved")
    public static let known = [added, modified, deleted, moved]
}

/// Where a plan's item stands. For one Ari doesn't know, treat it as pending.
public struct PlanItemState: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending = PlanItemState(rawValue: "pending")
    public static let inProgress = PlanItemState(rawValue: "in_progress")
    public static let done = PlanItemState(rawValue: "done")
    public static let known = [pending, inProgress, done]
}

/// What an ask is for. Ari treats a kind it doesn't know as a question.
public struct AskKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Information or a choice.
    public static let question = AskKind(rawValue: "question")
    /// Before the agent does something consequential, with a preview of what would happen.
    public static let approval = AskKind(rawValue: "approval")
    public static let known = [question, approval]
}

/// How an ask ended. An outcome Ari doesn't know means only that it ended.
public struct AskOutcome: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A message answered it.
    public static let answered = AskOutcome(rawValue: "answered")
    /// You cancelled it, or the agent asked something else.
    public static let cancelled = AskOutcome(rawValue: "cancelled")
    public static let known = [answered, cancelled]
}

/// What an attachment is. Ari treats a kind it doesn't know as a file.
public struct AttachmentKind: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A JPEG, PNG, GIF or WebP photo, which the agent sees.
    public static let image = AttachmentKind(rawValue: "image")
    /// Anything else, which lands in the agent's workspace.
    public static let file = AttachmentKind(rawValue: "file")
    public static let known = [image, file]
}
