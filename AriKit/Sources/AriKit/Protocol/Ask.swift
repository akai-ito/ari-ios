/// Something the agent asked you. Asking ends the agent's turn, and the ask waits as long as it
/// takes: the next message you send answers it, whether you tap an option, type your own answer, or
/// write about something else. At most one ask waits at a time.
public struct Ask: Hashable, Sendable, Decodable, Identifiable {
    public var id: AskID
    /// The turn that asked.
    public var turn: TurnID
    public var kind: AskKind
    /// Plain words, written by the agent.
    public var question: String
    /// Suggested answers, in order; empty when only a typed answer makes sense.
    public var options: [Option]
    /// Whether to offer a typed answer beside the options.
    public var allowsText: Bool
    /// Approvals only: what would happen, to show before you agree.
    public var preview: String?
    public var at: Timestamp
    /// Where it sits in the conversation, in one order with messages and steps.
    public var position: Int
    public var endedAt: Timestamp?
    /// How it ended; `nil` while it waits for your answer.
    public var outcome: AskOutcome?
    /// The message that answered it.
    public var answer: MessageID?

    /// A suggested answer. Tapping it sends its label as your message.
    public struct Option: Hashable, Sendable, Decodable {
        public var label: String
        public var description: String?
        /// Approvals only: this option goes ahead with the action, such as "Book it".
        public var acts: Bool

        public init(label: String, description: String? = nil, acts: Bool = false) {
            self.label = label
            self.description = description
            self.acts = acts
        }

        enum CodingKeys: String, CodingKey { case label, description, acts }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            acts = try container.decodeIfPresent(Bool.self, forKey: .acts) ?? false
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, turn, kind, question, options, preview, at, position, outcome, answer
        case allowsText = "allows_text"
        case endedAt = "ended_at"
    }
}

/// The answer to `POST /v0/asks/{ask}/cancel`: the ask, as it ended.
public struct AskResult: Sendable, Equatable, Decodable {
    public let ask: Ask
}
