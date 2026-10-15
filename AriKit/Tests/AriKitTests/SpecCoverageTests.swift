import AriKit
import Foundation
import Testing

/// Ari's models are written by hand, so these read the pinned spec itself. When the pin moves to a
/// spec with a new event type, a newly required field, or a new value for an enumeration, they fail
/// until the models catch up. A new optional field still needs a person to notice it.
@Suite("Keeping up with the spec")
struct SpecCoverageTests {
    @Test("Ari decodes exactly the event types the spec lists")
    func eventTypes() throws {
        let spec = try Spec()
        let references = try #require(spec.definitions["Event"]?["oneOf"]?.array).compactMap {
            $0["$ref"]?.string
        }
        let types = try references.map {
            try #require(spec.definition(at: $0)["properties"]?["type"]?["const"]?.string)
        }
        #expect(types.sorted() == Event.knownTypes.sorted())
    }

    /// Catches a model that insists on a field the spec makes optional, such as an error's detail,
    /// which every transcript happens to include.
    @Test(
        "every event decodes from only the fields the spec requires",
        arguments: try Fixtures.transcripts())
    func requiredFieldsOnly(_ transcript: Transcript) throws {
        let spec = try Spec()
        for logged in transcript.events {
            let type = try #require(logged.json["type"]?.string)
            let definition = try #require(spec.eventDefinition(type: type), "no schema for \(type)")
            let minimal = spec.keepingRequired(logged.json, schema: definition)
            let event = try minimal.decode(Event.self)
            #expect(event.payload.type == type, "\(transcript.name).jsonl line \(logged.line)")
        }
    }

    @Test("Ari knows every value of the spec's enumerations")
    func values() throws {
        let spec = try Spec()
        #expect(try spec.values(of: "Outcome") == Outcome.known.map(\.rawValue))
        #expect(try spec.values(of: "StatusKind") == StatusKind.known.map(\.rawValue))
        #expect(try spec.values(of: "MessageKind") == MessageKind.known.map(\.rawValue))
        let role = try #require(spec.definitions["Message"]?["properties"]?["role"]?["enum"]?.array)
        #expect(role.compactMap(\.string) == Role.known.map(\.rawValue))
        #expect(try spec.values(of: "StepKind") == StepKind.known.map(\.rawValue))
        let step = try #require(spec.definitions["Step"]?["properties"])
        func values(_ field: String, _ key: String) throws -> [String] {
            try #require(step[field]?["items"]?["properties"]?[key]?["enum"]?.array).compactMap(
                \.string)
        }
        #expect(try values("actions", "type") == ActionType.known.map(\.rawValue))
        #expect(try values("files", "change") == FileChangeKind.known.map(\.rawValue))
        #expect(try values("items", "state") == PlanItemState.known.map(\.rawValue))
        let reason = try #require(
            spec.definitions["Snapshot"]?["properties"]?["reason"]?["enum"]?.array)
        #expect(reason.compactMap(\.string) == SnapshotReason.known.map(\.rawValue))
        // The spec lists error codes in prose, each in backticks.
        let prose = try #require(spec.definitions["Error"]?["description"]?.string)
        let codes = prose.matches(of: /`([a-z][a-z0-9_]*)`/).map { String($0.output.1) }
        #expect(Set(codes) == Set(ErrorCode.known.map(\.rawValue)))
    }
}

/// protocol/events.schema.json, read just far enough for these checks.
private struct Spec {
    let definitions: [String: JSONValue]

    init() throws {
        definitions = try #require(Fixtures.eventsSchema()["$defs"]?.object)
    }

    func definition(at reference: String) throws -> JSONValue {
        let name = String(reference.split(separator: "/").last ?? "")
        return try #require(definitions[name], "no definition at \(reference)")
    }

    func eventDefinition(type: String) -> JSONValue? {
        definitions.values.first { $0["properties"]?["type"]?["const"]?.string == type }
    }

    func values(of name: String) throws -> [String] {
        try #require(definitions[name]?["enum"]?.array).compactMap(\.string)
    }

    /// `value` without the properties `schema` doesn't require, all the way down, following `$ref`,
    /// `oneOf` with null, and the `if`/`then` that makes `kind` and `turn` required on agent messages.
    func keepingRequired(_ value: JSONValue, schema: JSONValue) -> JSONValue {
        if let reference = schema["$ref"]?.string, let target = try? definition(at: reference) {
            return keepingRequired(value, schema: target)
        }
        if let branches = schema["oneOf"]?.array {
            guard value != .null,
                let branch = branches.first(where: { $0["type"]?.string != "null" })
            else {
                return value
            }
            return keepingRequired(value, schema: branch)
        }
        switch value {
        case .object(let object):
            var required = Set(schema["required"]?.array?.compactMap(\.string) ?? [])
            if let condition = schema["if"]?["properties"]?.object,
                condition.allSatisfy({ key, rule in object[key] == rule["const"] })
            {
                required.formUnion(schema["then"]?["required"]?.array?.compactMap(\.string) ?? [])
            }
            let properties = schema["properties"]?.object ?? [:]
            var kept: [String: JSONValue] = [:]
            for (key, child) in object where required.contains(key) {
                kept[key] = properties[key].map { keepingRequired(child, schema: $0) } ?? child
            }
            return .object(kept)
        case .array(let array):
            guard let items = schema["items"] else { return value }
            return .array(array.map { keepingRequired($0, schema: items) })
        default:
            return value
        }
    }
}
