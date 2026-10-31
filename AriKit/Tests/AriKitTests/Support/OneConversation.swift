import Foundation

// The pinned contract (ito-core#69 at e8302b0) still splits the conversation into spaces, which the
// server is rewriting out of 0.16 (plans#30). Until it publishes the one-conversation contract,
// this reads the pinned transcripts and events schema as that contract will have them: one
// conversation and the Desk. Only the tests use it, and Ari's code knows nothing of spaces.
//
// It goes when the server's one-conversation contract is pinned.

/// Reads a pinned 0.16 transcript, line by line, as one conversation.
///
/// - Events lose the space on their envelope. A snapshot's first space becomes the conversation,
///   beside the Desk. `space.changed` and `space.added` stay, as types Ari doesn't know, since the
///   transcripts resume from them.
/// - Sending and history in a space, and Tell Kumo, become `/v0/messages`; a call starts with no
///   body; marking a space read, and its answer, go.
///
/// The fields Ari no longer reads (a message's `filed`, the `space` of a call, a card, a briefing
/// line or a push) are left in: Ari ignores fields it doesn't know.
struct OneConversation {
    /// The event types that go with spaces.
    static let spaceEvents: Set<String> = ["space.changed", "space.added"]

    /// The last request's line, as the transcript has it.
    private var request: JSONValue?
    private var droppingAnswer = false

    /// The line as the one-conversation contract will have it, or `nil` for one it won't have.
    mutating func adapt(_ line: JSONValue) -> JSONValue? {
        var line = line
        if let event = line["given"] {
            line["given"] = Self.event(event)
        } else if let event = line["event"] {
            line["event"] = Self.event(event)
        } else if let request = line["app"] {
            self.request = request
            let path = request["path"]?.string ?? ""
            let parts = Self.parts(of: path)
            if request["method"] == "PUT", parts.count == 4, parts[1] == "spaces",
                parts[3] == "read"
            {
                droppingAnswer = true
                return nil
            }
            line["app"]?["path"] = .string(Self.path(path))
            if request["method"] == "PUT", parts.count == 3, parts[1] == "calls" {
                line["app"]?["body"] = nil
            }
        } else if line["server"] != nil {
            if droppingAnswer {
                droppingAnswer = false
                return nil
            }
            // Tell Kumo answered with the space it filed the message into.
            if request?["path"] == "/v0/desk/messages" {
                line["server"]?["body"]?["space"] = nil
            }
        }
        return line
    }

    /// An event without its space, and a snapshot as one conversation's.
    private static func event(_ event: JSONValue) -> JSONValue {
        var event = event
        if event["space"]?.string != nil { event["space"] = nil }
        if event["type"] == "snapshot", let first = event["spaces"]?.array?.first?.object {
            event["spaces"] = nil
            for (key, value) in first where key != "space" { event[key] = value }
        }
        return event
    }

    /// `/v0/spaces/{space}/messages` and `/v0/desk/messages` as `/v0/messages`, keeping a query.
    private static func path(_ path: String) -> String {
        let parts = parts(of: path)
        let query = path.firstIndex(of: "?").map { String(path[$0...]) } ?? ""
        if parts.count == 4, parts[1] == "spaces", parts[3] == "messages" {
            return "/v0/messages" + query
        }
        if parts == ["v0", "desk", "messages"] { return "/v0/messages" }
        return path
    }

    private static func parts(of path: String) -> [String] {
        let bare = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return bare.split(separator: "/").map(String.init)
    }

    /// The pinned events schema as the one-conversation contract will have it: no space events, and
    /// a snapshot holding the conversation's fields beside the Desk and getting started.
    static func schema(_ pinned: JSONValue) -> JSONValue {
        var schema = pinned
        guard var definitions = pinned["$defs"]?.object else { return pinned }
        let spaceEventReferences = definitions.compactMap { name, definition in
            spaceEvents.contains(definition["properties"]?["type"]?["const"]?.string ?? "")
                ? "#/$defs/\(name)" : nil
        }
        if let events = definitions["Event"]?["oneOf"]?.array {
            definitions["Event"]?["oneOf"] = .array(
                events.filter { !spaceEventReferences.contains($0["$ref"]?.string ?? "") })
        }
        if var snapshot = definitions["Snapshot"], let part = definitions["SpaceConversation"] {
            let required = (snapshot["required"]?.array ?? []).filter { $0 != "spaces" }
            let partRequired = (part["required"]?.array ?? []).filter { $0 != "space" }
            snapshot["required"] = .array(required + partRequired)
            var properties = snapshot["properties"]?.object ?? [:]
            properties["spaces"] = nil
            for (key, value) in part["properties"]?.object ?? [:] where key != "space" {
                properties[key] = value
            }
            properties["onboarding"] = .object(["$ref": "#/$defs/Onboarding"])
            snapshot["properties"] = .object(properties)
            definitions["Snapshot"] = snapshot
        }
        schema["$defs"] = .object(definitions)
        return schema
    }
}
