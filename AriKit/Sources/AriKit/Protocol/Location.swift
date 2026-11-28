import Foundation

// The trail the phone collects, as it goes up to the box.

/// A batch of the trail's id, made on the phone (a random UUID), which is also its retry key.
public struct TrailBatchID: OpaqueIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A batch of the trail. Its id makes sending it again harmless: the box keeps each batch once.
public struct TrailBatch: Sendable, Equatable, Codable {
    public let id: TrailBatchID
    /// The phone's time zone when the batch was started, so the box knows your local days.
    public var timeZone: String
    public var points: [TrailPoint]
    public var visits: [TrailVisit]

    public init(
        id: TrailBatchID, timeZone: String = TimeZone.current.identifier,
        points: [TrailPoint] = [], visits: [TrailVisit] = []
    ) {
        self.id = id
        self.timeZone = timeZone
        self.points = points
        self.visits = visits
    }

    public var count: Int { points.count + visits.count }
    public var isEmpty: Bool { points.isEmpty && visits.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id = "batch"
        case timeZone = "time_zone"
        case points = "samples"
        case visits
    }
}

extension TrailPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case at, latitude, longitude, accuracy, altitude, speed, course, source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            at: try container.decode(Timestamp.self, forKey: .at).date,
            latitude: try container.decode(Double.self, forKey: .latitude),
            longitude: try container.decode(Double.self, forKey: .longitude),
            accuracy: try container.decode(Double.self, forKey: .accuracy),
            altitude: try container.decodeIfPresent(Double.self, forKey: .altitude),
            speed: try container.decodeIfPresent(Double.self, forKey: .speed),
            course: try container.decodeIfPresent(Double.self, forKey: .course),
            source: try container.decode(Source.self, forKey: .source))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Timestamp(at), forKey: .at)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(speed, forKey: .speed)
        try container.encodeIfPresent(course, forKey: .course)
        try container.encode(source, forKey: .source)
    }
}

extension TrailVisit: Codable {
    enum CodingKeys: String, CodingKey {
        case arrived = "arrived_at"
        case departed = "departed_at"
        case latitude, longitude, accuracy, placemark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            arrived: try container.decodeIfPresent(Timestamp.self, forKey: .arrived)?.date,
            departed: try container.decodeIfPresent(Timestamp.self, forKey: .departed)?.date,
            latitude: try container.decode(Double.self, forKey: .latitude),
            longitude: try container.decode(Double.self, forKey: .longitude),
            accuracy: try container.decode(Double.self, forKey: .accuracy),
            placemark: try container.decodeIfPresent(Placemark.self, forKey: .placemark))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(placemark, forKey: .placemark)
        try container.encodeIfPresent(arrived.map(Timestamp.init), forKey: .arrived)
        try container.encodeIfPresent(departed.map(Timestamp.init), forKey: .departed)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(accuracy, forKey: .accuracy)
    }
}

/// Apple's name for a spot, read on the phone: the box has no map data of its own. Each part is
/// trimmed to the length the box takes.
public struct Placemark: Sendable, Equatable, Hashable, Codable {
    /// The place itself, such as a café, or an address.
    public var name: String?
    /// Its MapKit point-of-interest category without the `MKPOICategory` prefix, such as
    /// `Restaurant`.
    public var category: String?
    public var street: String?
    public var locality: String?
    /// The region, such as Scotland.
    public var area: String?
    public var country: String?
    /// ISO 3166-1 alpha-2, such as `GB`.
    public var countryCode: String?

    public init(
        name: String? = nil, category: String? = nil, street: String? = nil,
        locality: String? = nil, area: String? = nil, country: String? = nil,
        countryCode: String? = nil
    ) {
        self.name = Self.clip(name, 120)
        self.category = Self.clip(category, 64)
        self.street = Self.clip(street, 120)
        self.locality = Self.clip(locality, 80)
        self.area = Self.clip(area, 80)
        self.country = Self.clip(country, 80)
        let code = countryCode?.uppercased()
        self.countryCode =
            code.map { $0.count == 2 && $0.allSatisfy { ("A"..."Z").contains($0) } } == true
            ? code : nil
    }

    /// Whether Apple said anything at all.
    public var isEmpty: Bool {
        [name, category, street, locality, area, country, countryCode].allSatisfy { $0 == nil }
    }

    private static func clip(_ text: String?, _ length: Int) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return String(text.prefix(length))
    }

    enum CodingKeys: String, CodingKey {
        case name, category, street, locality, area, country
        case countryCode = "country_code"
    }
}

/// The body of `POST /v0/location/photos`: where and when photos were taken, to seed the past.
public struct PhotoSeeds: Sendable, Equatable, Codable {
    public let batch: String
    /// The photos' local days are read in this time zone.
    public let timeZone: String
    public let photos: [PhotoSeed]

    public init(batch: String, timeZone: String = TimeZone.current.identifier, photos: [PhotoSeed])
    {
        self.batch = batch
        self.timeZone = timeZone
        self.photos = photos
    }

    enum CodingKeys: String, CodingKey {
        case batch, photos
        case timeZone = "time_zone"
    }
}

/// One photo's when and where, from its metadata.
public struct PhotoSeed: Sendable, Equatable, Codable {
    public var takenAt: Date
    public var latitude: Double
    public var longitude: Double
    public var placemark: Placemark?

    public init(takenAt: Date, latitude: Double, longitude: Double, placemark: Placemark? = nil) {
        self.takenAt = takenAt
        self.latitude = latitude
        self.longitude = longitude
        self.placemark = placemark
    }

    enum CodingKeys: String, CodingKey {
        case takenAt = "taken_at"
        case latitude, longitude, placemark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takenAt = try container.decode(Timestamp.self, forKey: .takenAt).date
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        placemark = try container.decodeIfPresent(Placemark.self, forKey: .placemark)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Timestamp(takenAt), forKey: .takenAt)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(placemark, forKey: .placemark)
    }
}

/// The body of `POST /v0/location/forget`: a day, a range of days (both ends included), or
/// everything. Days are your local days, as `YYYY-MM-DD`.
public enum ForgetLocation: Sendable, Equatable, Codable {
    case day(String)
    case range(from: String, to: String)
    case everything

    enum CodingKeys: String, CodingKey {
        case day, from, to, everything
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let day = try container.decodeIfPresent(String.self, forKey: .day) {
            self = .day(day)
        } else if let from = try container.decodeIfPresent(String.self, forKey: .from) {
            self = .range(from: from, to: try container.decode(String.self, forKey: .to))
        } else {
            self = .everything
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .day(let day):
            try container.encode(day, forKey: .day)
        case .range(let from, let to):
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .everything:
            try container.encode(true, forKey: .everything)
        }
    }
}

/// What the box keeps of where you've been, from `GET /v0/location`, for Settings.
public struct LocationHeld: Sendable, Equatable, Decodable {
    public let samples: Int
    public let visits: Int
    public let photos: Int
    public let places: Int
    /// The first and last days it has, as `YYYY-MM-DD`.
    public let firstDay: String?
    public let lastDay: String?
    /// When it last took a batch.
    public let uploadedAt: Timestamp?

    enum CodingKeys: String, CodingKey {
        case samples, visits, photos, places
        case firstDay = "first_day"
        case lastDay = "last_day"
        case uploadedAt = "uploaded_at"
    }
}
