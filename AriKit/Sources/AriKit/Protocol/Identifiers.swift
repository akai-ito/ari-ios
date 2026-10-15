/// An identifier from the protocol: opaque text, compared only for equality and never parsed.
public protocol OpaqueIdentifier:
    RawRepresentable<String>, Hashable, Sendable, Codable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    init(rawValue: String)
}

extension OpaqueIdentifier {
    public init(_ rawValue: String) { self.init(rawValue: rawValue) }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
}

/// An event's place in the server's log, never reused. Send the last one applied as
/// `Last-Event-ID` to resume.
public struct EventID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A message's permanent id. Ari makes the ids of the messages you send (a random UUID, which is
/// also the retry key); the server makes the ids of the agent's.
public struct MessageID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One run of the agent, from its inputs to an answer, a stop or an error. Stop and Try again are
/// addressed to it.
public struct TurnID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One thing the agent did while working on a turn. The server makes it when the step starts.
public struct StepID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Something the agent asked you. The server makes it when the agent asks.
public struct AskID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
