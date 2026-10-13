import Foundation

/// Any JSON value, so tests can read a transcript line, change it, and decode it again.
enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    init(json: String) throws {
        try self.init(data: Data(json.utf8))
    }

    /// Encodes `value` and reads the result back as JSON.
    init(encoding value: some Encodable) throws {
        try self.init(data: JSONEncoder().encode(value))
    }

    subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let object) = self else { return nil }
            return object[key]
        }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    var string: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var int: Int? {
        guard case .int(let int) = self else { return nil }
        return int
    }

    var array: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var object: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

extension JSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .int(let int): try container.encode(int)
        case .double(let double): try container.encode(double)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}
