import Foundation

/// One point of the trail: where the phone was, when, and how sure it was.
public struct TrailPoint: Sendable, Equatable, Hashable {
    /// Where a point came from.
    public enum Source: String, Sendable, Codable, Hashable {
        /// Live GPS while moving, or a fix read when Ito opened.
        case live
        /// A significant change, about 500 m on, hundreds of metres coarse.
        case change
    }

    public var at: Date
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy in metres.
    public var accuracy: Double
    public var altitude: Double?
    /// Metres per second, when known.
    public var speed: Double?
    /// Degrees from north, when known.
    public var course: Double?
    public var source: Source

    public init(
        at: Date, latitude: Double, longitude: Double, accuracy: Double, altitude: Double? = nil,
        speed: Double? = nil, course: Double? = nil, source: Source
    ) {
        self.at = at
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.altitude = altitude
        self.speed = speed.flatMap { $0 >= 0 ? $0 : nil }
        self.course = course.flatMap { $0 >= 0 ? $0 : nil }
        self.source = source
    }

    /// Metres to `other`, along the ground.
    public func metres(from other: TrailPoint) -> Double {
        Self.metres(latitude, longitude, other.latitude, other.longitude)
    }

    /// Metres between two places, by the haversine formula.
    public static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double)
        -> Double
    {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a =
            sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A stop iOS noticed: where, and from when to when. iOS often says the arrival first and the
/// same visit again once you leave, with its departure; the box keeps the later one.
public struct TrailVisit: Sendable, Equatable, Hashable {
    /// `nil` when iOS doesn't know when you arrived, as for a visit under way at launch.
    public var arrived: Date?
    /// `nil` until you leave.
    public var departed: Date?
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy in metres.
    public var accuracy: Double
    /// Apple's name for the spot, read on the phone, when it could be.
    public var placemark: Placemark?

    public init(
        arrived: Date?, departed: Date?, latitude: Double, longitude: Double, accuracy: Double,
        placemark: Placemark? = nil
    ) {
        self.arrived = arrived
        self.departed = departed
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.placemark = placemark
    }

    /// When it's for: its arrival, else its departure.
    public var at: Date? { arrived ?? departed }

    /// The same visit, whichever of its deliveries: by arrival when iOS gave one, else by place and
    /// departure.
    public var key: String {
        let place = String(format: "%.4f,%.4f", latitude, longitude)
        if let arrived { return "a\(Int(arrived.timeIntervalSince1970))@\(place)" }
        return "d\(Int((departed ?? .distantPast).timeIntervalSince1970))@\(place)"
    }
}
