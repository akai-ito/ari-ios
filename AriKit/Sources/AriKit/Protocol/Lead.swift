import Foundation

// The settings you make for Kumo itself: what it's called.

/// The lead you talk to: Kumo until you choose another name. `GET /v0/server`'s `lead`, and the
/// body and answer of `PUT /v0/lead`.
public struct Lead: Sendable, Equatable, Codable {
    public let name: String

    public init(name: String) { self.name = name }
}
