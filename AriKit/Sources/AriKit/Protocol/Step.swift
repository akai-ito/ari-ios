import Foundation

/// One thing the agent did while working on a turn: thinking, a web search, a command, an edit, a
/// tool, a plan, a wait. Its title is plain words written by the server, safe to show as it is; the
/// other fields carry the specifics exactly as the agent used them, and a step has those of its kind.
/// Every step event carries the whole step as it now stands.
public struct Step: Hashable, Sendable, Decodable, Identifiable {
    public var id: StepID
    /// The turn it belongs to.
    public var turn: TurnID
    public var kind: StepKind
    /// Present tense while it runs ("Reading notes.md"), past tense once it has ended.
    public var title: String
    /// When it began.
    public var at: Timestamp
    /// Where it sits in the conversation, in one order with the messages.
    public var position: Int
    public var endedAt: Timestamp?
    /// How it ended; `nil` while it runs.
    public var outcome: Outcome?
    public var durationMs: Int?
    /// When it failed, what went wrong, in the tool's or command's own words.
    public var detail: String?

    // thinking
    /// The heading the model gave its reasoning.
    public var heading: String?
    /// The model's summary of its reasoning, in Markdown, as far as it has been written.
    public var summary: String?
    // web_search
    public var query: String?
    public var queries: [String]?
    /// The page opened, or searched within.
    public var url: String?
    /// The words looked for on a page.
    public var pattern: String?
    public var results: [SearchResult]?
    // command
    /// The command line, exactly as run.
    public var command: String?
    public var cwd: String?
    public var actions: [Action]?
    public var exitCode: Int?
    /// The end of what it printed, at most the last 2 KB, once it has ended.
    public var output: String?
    // file_change
    public var files: [FileChange]?
    // tool
    /// The capability the tool belongs to, such as a server's name.
    public var capability: String?
    public var operation: String?
    /// The arguments it was called with, as JSON text.
    public var arguments: String?
    // plan
    public var explanation: String?
    public var items: [PlanItem]?
    // wait
    public var waitMs: Int?
    // image_view
    /// The image looked at.
    public var path: String?
    // memory
    /// What memory did: the pages used in this reply, a page updated, or the journal added to.
    public var memoryAction: MemoryAction?
    /// The pages it used or updated, without their words.
    public var pages: [PageSummary]?
    /// For an update, the change to fetch when you open it.
    public var change: String?
    // motion
    /// The thing in motion Ari started or changed, for `memoryAction` started, updated or finished.
    public var motion: MotionID?
    /// The thing's version after the change.
    public var version: Int?
    /// Ari's note on the change, such as "Booked the Uffizi, 8:15 Saturday".
    public var note: String?

    public struct SearchResult: Hashable, Sendable, Decodable {
        public var title: String?
        public var url: String
    }

    public struct Action: Hashable, Sendable, Decodable {
        public var type: ActionType
        public var path: String?
        public var query: String?
    }

    public struct FileChange: Hashable, Sendable, Decodable {
        public var path: String
        public var change: FileChangeKind
        /// For a moved file, where it was.
        public var from: String?
        public var linesAdded: Int?
        public var linesRemoved: Int?

        enum CodingKeys: String, CodingKey {
            case path, change, from
            case linesAdded = "lines_added"
            case linesRemoved = "lines_removed"
        }
    }

    public struct PlanItem: Hashable, Sendable, Decodable {
        public var text: String
        public var state: PlanItemState
    }

    /// A step as it begins, for tests and previews; set the kind's fields afterwards.
    public init(
        id: StepID, turn: TurnID, kind: StepKind, title: String, at: Timestamp, position: Int
    ) {
        self.id = id
        self.turn = turn
        self.kind = kind
        self.title = title
        self.at = at
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case id, turn, kind, title, at, position, outcome, detail
        case heading, summary, query, queries, url, pattern, results
        case command, cwd, actions, output, files, capability, operation, arguments
        case explanation, items, path, pages, change, motion, version, note
        case memoryAction = "action"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case exitCode = "exit_code"
        case waitMs = "wait_ms"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(StepID.self, forKey: .id)
        turn = try c.decode(TurnID.self, forKey: .turn)
        kind = try c.decode(StepKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        at = try c.decode(Timestamp.self, forKey: .at)
        position = try c.decode(Int.self, forKey: .position)
        endedAt = try c.decodeIfPresent(Timestamp.self, forKey: .endedAt)
        outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        heading = try c.decodeIfPresent(String.self, forKey: .heading)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        queries = try c.decodeIfPresent([String].self, forKey: .queries)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern)
        results = try c.decodeIfPresent([SearchResult].self, forKey: .results)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        actions = try c.decodeIfPresent([Action].self, forKey: .actions)
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        output = try c.decodeIfPresent(String.self, forKey: .output)
        files = try c.decodeIfPresent([FileChange].self, forKey: .files)
        capability = try c.decodeIfPresent(String.self, forKey: .capability)
        operation = try c.decodeIfPresent(String.self, forKey: .operation)
        arguments = try c.decodeIfPresent(AnyJSON.self, forKey: .arguments)?.text
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items)
        waitMs = try c.decodeIfPresent(Int.self, forKey: .waitMs)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        memoryAction = try c.decodeIfPresent(MemoryAction.self, forKey: .memoryAction)
        pages = try c.decodeIfPresent([PageSummary].self, forKey: .pages)
        change = try c.decodeIfPresent(String.self, forKey: .change)
        motion = try c.decodeIfPresent(MotionID.self, forKey: .motion)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// Any JSON value, read only to be shown again as text.
private enum AnyJSON: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AnyJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Pretty-printed, keys sorted, slashes left alone.
    var text: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
