/// A version of the Ito client protocol, `MAJOR.MINOR`. Until 1.0 every change may break, so an app
/// and a server must speak the same `0.MINOR`.
public struct ProtocolVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    /// The version this build of Ari speaks.
    public static let supported = ProtocolVersion(major: 0, minor: 14)

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Reads `MAJOR.MINOR`, as in the `Ito-Protocol` header; anything else is `nil`.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
            parts.allSatisfy({
                !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber)
            }),
            let major = Int(parts[0]), let minor = Int(parts[1])
        else { return nil }
        self.init(major: major, minor: minor)
    }

    public var description: String { "\(major).\(minor)" }

    public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

extension ProtocolVersion: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let version = ProtocolVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(text)\" is not a MAJOR.MINOR protocol version.")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
