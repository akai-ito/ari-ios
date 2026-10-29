import Foundation

/// A day, a weekend or a longer trip: its days, places, travel, stay and what's left to do. Ari
/// writes it, an item at a time; your ticks on the to-do list are in the thing's state.
public struct Trip: Sendable, Equatable, Decodable {
    /// Such as "Florence".
    public let destination: String
    public let dates: Dates
    /// An IANA time zone, such as `Europe/Rome`: every time in the trip is local to it.
    public let timezone: String
    /// Who's going besides you.
    public let who: [String]
    /// A big photo of the place, for the header and the card.
    public let cover: Photo?
    public let days: [Day]
    public let places: [Place]
    public let travel: [Leg]
    public let stays: [Stay]
    public let todo: [Todo]

    public init(
        destination: String, dates: Dates, timezone: String, who: [String] = [],
        cover: Photo? = nil, days: [Day] = [], places: [Place] = [], travel: [Leg] = [],
        stays: [Stay] = [], todo: [Todo] = []
    ) {
        self.destination = destination
        self.dates = dates
        self.timezone = timezone
        self.who = who
        self.cover = cover
        self.days = days
        self.places = places
        self.travel = travel
        self.stays = stays
        self.todo = todo
    }

    /// The first and last days, such as `2026-11-06` and `2026-11-09`.
    public struct Dates: Sendable, Equatable, Decodable {
        public let start: String
        public let end: String

        public init(start: String, end: String) {
            self.start = start
            self.end = end
        }
    }

    /// One day, its stops in order.
    public struct Day: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        /// Such as `2026-11-06`.
        public let date: String
        /// Such as "Pisa".
        public let title: String?
        public let stops: [Stop]

        public init(id: String, date: String, title: String? = nil, stops: [Stop] = []) {
            self.id = id
            self.date = date
            self.title = title
            self.stops = stops
        }
    }

    /// One stop in a day: a visit, a meal, a train.
    public struct Stop: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let title: String
        /// Local, such as `08:15`.
        public let time: String?
        /// The id of its place in ``Trip/places``.
        public let place: String?
        public let note: String?
        public let booking: Booking?
        /// Getting to the next stop.
        public let next: Move?

        public init(
            id: String, title: String, time: String? = nil, place: String? = nil,
            note: String? = nil, booking: Booking? = nil, next: Move? = nil
        ) {
            self.id = id
            self.title = title
            self.time = time
            self.place = place
            self.note = note
            self.booking = booking
            self.next = next
        }
    }

    /// Getting from one stop to the next, such as a 12 minute walk.
    public struct Move: Sendable, Equatable, Decodable {
        public let mode: TravelMode
        public let minutes: Int?
        /// Such as "Firenze SMN → Pisa Centrale".
        public let detail: String?

        public init(mode: TravelMode, minutes: Int? = nil, detail: String? = nil) {
            self.mode = mode
            self.minutes = minutes
            self.detail = detail
        }
    }

    /// A place Ari found: a restaurant, a museum, a sight.
    public struct Place: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let name: String
        public let category: PlaceCategory
        /// Why Ari chose it, in a line.
        public let why: String
        public let status: PlaceStatus
        /// Such as "8:15–18:30".
        public let hours: String?
        /// Such as "€25" or "€€".
        public let price: String?
        public let address: String?
        public let location: Location?
        public let url: URL?
        public let photo: Photo?
        public let booking: Booking?

        public init(
            id: String, name: String, category: PlaceCategory = .other, why: String,
            status: PlaceStatus = .shortlisted, hours: String? = nil, price: String? = nil,
            address: String? = nil, location: Location? = nil, url: URL? = nil,
            photo: Photo? = nil, booking: Booking? = nil
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.why = why
            self.status = status
            self.hours = hours
            self.price = price
            self.address = address
            self.location = location
            self.url = url
            self.photo = photo
            self.booking = booking
        }
    }

    /// Getting there and around: a flight, a train, a transfer.
    public struct Leg: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let mode: TravelMode
        /// Such as "Train to Pisa".
        public let title: String
        public let from: String?
        public let to: String?
        /// Local, such as `2026-11-08T09:12`.
        public let depart: String?
        public let arrive: String?
        public let booking: Booking?
        public let note: String?

        public init(
            id: String, mode: TravelMode, title: String, from: String? = nil, to: String? = nil,
            depart: String? = nil, arrive: String? = nil, booking: Booking? = nil,
            note: String? = nil
        ) {
            self.id = id
            self.mode = mode
            self.title = title
            self.from = from
            self.to = to
            self.depart = depart
            self.arrive = arrive
            self.booking = booking
            self.note = note
        }
    }

    /// Where you're staying.
    public struct Stay: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let name: String
        public let address: String?
        public let location: Location?
        /// Local, such as `2026-11-06T15:00`.
        public let checkIn: String?
        public let checkOut: String?
        public let url: URL?
        public let photo: Photo?
        public let booking: Booking?

        public init(
            id: String, name: String, address: String? = nil, location: Location? = nil,
            checkIn: String? = nil, checkOut: String? = nil, url: URL? = nil,
            photo: Photo? = nil, booking: Booking? = nil
        ) {
            self.id = id
            self.name = name
            self.address = address
            self.location = location
            self.checkIn = checkIn
            self.checkOut = checkOut
            self.url = url
            self.photo = photo
            self.booking = booking
        }

        enum CodingKeys: String, CodingKey {
            case id, name, address, location, url, photo, booking
            case checkIn = "check_in"
            case checkOut = "check_out"
        }
    }

    /// Something left to do. `done` is how Ari wrote it; your tick, in the state, wins.
    public struct Todo: Sendable, Equatable, Decodable, Identifiable {
        public let id: String
        public let text: String
        public let done: Bool
        /// The stops, legs, stays or places it books, by id: they show booked once it's ticked.
        public let about: [String]

        public init(id: String, text: String, done: Bool = false, about: [String] = []) {
            self.id = id
            self.text = text
            self.done = done
            self.about = about
        }

        enum CodingKeys: String, CodingKey { case id, text, done, about }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            done = try c.decode(Bool.self, forKey: .done)
            about = try c.decodeIfPresent([String].self, forKey: .about) ?? []
        }
    }

    /// Whether something needs booking, and where that stands.
    public struct Booking: Sendable, Equatable, Decodable {
        public let status: BookingStatus
        /// Such as `ABC123`.
        public let ref: String?
        public let url: URL?

        public init(status: BookingStatus, ref: String? = nil, url: URL? = nil) {
            self.status = status
            self.ref = ref
            self.url = url
        }
    }

    public struct Location: Sendable, Equatable, Decodable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }
}

/// A picture Ari found on the web and kept on the server, never made. Its credit shows when you tap
/// it.
public struct Photo: Sendable, Equatable, Decodable {
    public let attachment: AttachmentID
    public let alt: String
    /// The page the picture came from.
    public let sourceURL: URL
    /// Who made it, as its source asks.
    public let credit: String

    public init(attachment: AttachmentID, alt: String, sourceURL: URL, credit: String) {
        self.attachment = attachment
        self.alt = alt
        self.sourceURL = sourceURL
        self.credit = credit
    }

    enum CodingKeys: String, CodingKey {
        case attachment, alt, credit
        case sourceURL = "source_url"
    }
}

/// How you get somewhere. Ari draws one it doesn't know as a plain arrow.
public struct TravelMode: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let walk = TravelMode(rawValue: "walk")
    public static let train = TravelMode(rawValue: "train")
    public static let tram = TravelMode(rawValue: "tram")
    public static let bus = TravelMode(rawValue: "bus")
    public static let metro = TravelMode(rawValue: "metro")
    public static let car = TravelMode(rawValue: "car")
    public static let taxi = TravelMode(rawValue: "taxi")
    public static let bike = TravelMode(rawValue: "bike")
    public static let ferry = TravelMode(rawValue: "ferry")
    public static let flight = TravelMode(rawValue: "flight")
    public static let known = [walk, train, tram, bus, metro, car, taxi, bike, ferry, flight]
}

/// What kind of place Ari found.
public struct PlaceCategory: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let restaurant = PlaceCategory(rawValue: "restaurant")
    public static let cafe = PlaceCategory(rawValue: "cafe")
    public static let bar = PlaceCategory(rawValue: "bar")
    public static let museum = PlaceCategory(rawValue: "museum")
    public static let sight = PlaceCategory(rawValue: "sight")
    public static let park = PlaceCategory(rawValue: "park")
    public static let shop = PlaceCategory(rawValue: "shop")
    public static let activity = PlaceCategory(rawValue: "activity")
    public static let other = PlaceCategory(rawValue: "other")
    public static let known = [
        restaurant, cafe, bar, museum, sight, park, shop, activity, other,
    ]
}

/// Where a place stands: one Ari found, one you're going to, one that's booked.
public struct PlaceStatus: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let shortlisted = PlaceStatus(rawValue: "shortlisted")
    public static let picked = PlaceStatus(rawValue: "picked")
    public static let booked = PlaceStatus(rawValue: "booked")
    public static let known = [shortlisted, picked, booked]
}

/// Whether something still needs booking.
public struct BookingStatus: OpenValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let toBook = BookingStatus(rawValue: "to_book")
    public static let booked = BookingStatus(rawValue: "booked")
    public static let notNeeded = BookingStatus(rawValue: "not_needed")
    public static let known = [toBook, booked, notNeeded]
}
