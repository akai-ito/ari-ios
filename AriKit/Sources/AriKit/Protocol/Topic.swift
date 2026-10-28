import Foundation

public struct TopicID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Where the subject changed: a quiet label Ari puts on the message that changed it. A label used
/// again is the same subject, returned to.
public struct Topic: Sendable, Hashable, Identifiable, Decodable {
    public let id: TopicID
    /// One to four words, such as "Florence trip", safe to show as it is.
    public let label: String
    /// The position of the message that changed the subject: the label goes above it.
    public let position: Int
    public let at: Timestamp

    public init(id: TopicID, label: String, position: Int, at: Timestamp) {
        self.id = id
        self.label = label
        self.position = position
        self.at = at
    }
}

/// `topic.started`: Ari marked where the subject changed, while answering the message that changed
/// it.
public struct TopicStarted: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let topic: Topic
}
