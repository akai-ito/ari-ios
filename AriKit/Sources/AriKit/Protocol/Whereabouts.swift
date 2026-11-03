import Foundation

// Where the phone roughly is: its time zone, which Kumo lives by, and, when you allow it, a place
// rounded to about 10 km, for the weather on the Desk. Nothing more precise ever leaves the phone.

/// The body of `PUT /v0/devices/{device}/whereabouts`.
public struct Whereabouts: Sendable, Equatable, Codable {
    /// The phone's time zone, as an IANA name such as `Europe/Rome`.
    public let timeZone: String
    /// Roughly where it is, when you allow it.
    public let area: Area?

    public init(timeZone: String, area: Area? = nil) {
        self.timeZone = timeZone
        self.area = area
    }

    enum CodingKeys: String, CodingKey {
        case area
        case timeZone = "time_zone"
    }
}

/// Roughly where you are, never more precise than about 10 km.
public struct Area: Sendable, Equatable, Codable {
    public let latitude: Double
    public let longitude: Double
    /// The town or city, such as `Rome`, as the phone names it.
    public let name: String?

    /// A place rounded to one decimal, about 10 km, before it leaves the phone.
    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

/// What the box keeps of where you roughly are, from `GET /v0/server`, once a phone has said.
public struct KeptWhereabouts: Sendable, Equatable, Codable {
    public let timeZone: String
    public let area: Area?
    /// When a phone last said.
    public let asOf: Timestamp

    enum CodingKeys: String, CodingKey {
        case area
        case timeZone = "time_zone"
        case asOf = "as_of"
    }
}
