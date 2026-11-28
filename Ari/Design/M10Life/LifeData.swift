#if DEBUG
    import CoreLocation
    import MapKit
    import SwiftUI

    /// Made-up places in a real city's streets, for Milestone 10's stills. None of them is anyone's
    /// real home, office or haunt, and every name is invented.
    struct LifePlace: Identifiable, Hashable {
        let id: String
        /// Kumo's name for it.
        let name: String
        /// What it is, and where, in a few words.
        let what: String
        let symbol: String
        let lat: Double
        let lon: Double

        var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    enum LifeData {
        static let home = LifePlace(
            id: "home", name: "Home", what: "Marchmont", symbol: "house.fill", lat: 55.9362,
            lon: -3.1925)
        static let office = LifePlace(
            id: "office", name: "The office", what: "Hearthside co-work · New Town",
            symbol: "building.2.fill", lat: 55.9530, lon: -3.2000)
        static let cafe = LifePlace(
            id: "cafe", name: "The morning café", what: "Copperleaf · Lauriston",
            symbol: "cup.and.saucer.fill", lat: 55.9445, lon: -3.1960)
        static let northwind = LifePlace(
            id: "northwind", name: "Northwind", what: "Their office · the Shore",
            symbol: "briefcase.fill", lat: 55.9760, lon: -3.1730)
        static let gym = LifePlace(
            id: "gym", name: "The gym", what: "Leith Walk", symbol: "dumbbell.fill",
            lat: 55.9625, lon: -3.1795)
        static let meadows = LifePlace(
            id: "meadows", name: "The Meadows loop", what: "Where you run",
            symbol: "figure.run", lat: 55.9412, lon: -3.1905)
        static let leo = LifePlace(
            id: "leo", name: "Leo's", what: "Leith", symbol: "person.fill", lat: 55.9712,
            lon: -3.1655)
        static let orrins = LifePlace(
            id: "orrins", name: "Orrin's", what: "Dinner · Stockbridge",
            symbol: "fork.knife", lat: 55.9585, lon: -3.2090)
        static let mira = LifePlace(
            id: "mira", name: "Mira's", what: "Bruntsfield", symbol: "person.fill",
            lat: 55.9368, lon: -3.2085)
        static let hill = LifePlace(
            id: "hill", name: "The hill", what: "Sunday walks", symbol: "mountain.2.fill",
            lat: 55.9441, lon: -3.1618)
        static let unknown = LifePlace(
            id: "unknown", name: "Somewhere in Dalry", what: "Not named yet",
            symbol: "questionmark", lat: 55.9436, lon: -3.2215)
        static let market = LifePlace(
            id: "market", name: "Somewhere off Leith Walk", what: "Not named yet",
            symbol: "questionmark", lat: 55.9668, lon: -3.1748)

        static let city = MKCoordinateRegion(
            center: .init(latitude: 55.9535, longitude: -3.1880),
            span: .init(latitudeDelta: 0.052, longitudeDelta: 0.075))
        static let todayRegion = MKCoordinateRegion(
            center: .init(latitude: 55.9565, longitude: -3.1860),
            span: .init(latitudeDelta: 0.046, longitudeDelta: 0.05))
        static let europe = MKCoordinateRegion(
            center: .init(latitude: 48.6, longitude: -4.6),
            span: .init(latitudeDelta: 22, longitudeDelta: 20))
        static let hillRegion = MKCoordinateRegion(
            center: .init(latitude: 55.9430, longitude: -3.1780),
            span: .init(latitudeDelta: 0.019, longitudeDelta: 0.042))

        // MARK: Today, a Tuesday

        /// Where you were today, stop by stop, in hours since midnight. The last one is now.
        struct Stop: Identifiable {
            var id: String { place.id + "\(from)" }
            let place: LifePlace
            let from: Double
            let to: Double?
            var note: String?
            var ahead = false

            var minutes: Int { Int((((to ?? 16.5) - from) * 60).rounded()) }
        }

        static let today: [Stop] = [
            Stop(place: cafe, from: 8 + 10 / 60, to: 9),
            Stop(place: office, from: 9 + 20 / 60, to: 13 + 25 / 60),
            Stop(place: northwind, from: 13 + 50 / 60, to: 15 + 10 / 60, note: "Northwind final"),
            Stop(place: office, from: 15 + 40 / 60, to: nil),
            Stop(place: meadows, from: 17.5, to: 18.25, note: "Run with Leo", ahead: true),
            Stop(place: orrins, from: 19.5, to: 21, note: "Dinner with Mira", ahead: true),
        ]

        static let homeToCafe: [CLLocationCoordinate2D] = [
            (55.9362, -3.1925), (55.9378, -3.1921), (55.9392, -3.1919), (55.9404, -3.1934),
            (55.9418, -3.1945), (55.9432, -3.1952), (55.9445, -3.1960),
        ].map { .init(latitude: $0.0, longitude: $0.1) }

        static let cafeToOffice: [CLLocationCoordinate2D] = [
            (55.9445, -3.1960), (55.9452, -3.1925), (55.9466, -3.1915), (55.9482, -3.1918),
            (55.9496, -3.1926), (55.9506, -3.1938), (55.9516, -3.1952), (55.9525, -3.1968),
            (55.9530, -3.2000),
        ].map { .init(latitude: $0.0, longitude: $0.1) }

        static let officeToNorthwind: [CLLocationCoordinate2D] = [
            (55.9530, -3.2000), (55.9540, -3.1958), (55.9550, -3.1915), (55.9563, -3.1880),
            (55.9582, -3.1848), (55.9604, -3.1820), (55.9628, -3.1792), (55.9652, -3.1770),
            (55.9678, -3.1752), (55.9705, -3.1735), (55.9728, -3.1722), (55.9748, -3.1720),
            (55.9760, -3.1730),
        ].map { .init(latitude: $0.0, longitude: $0.1) }

        static var northwindToOffice: [CLLocationCoordinate2D] {
            officeToNorthwind.reversed().map {
                .init(latitude: $0.latitude, longitude: $0.longitude + 0.0006)
            }
        }

        static var todayTrail: [[CLLocationCoordinate2D]] {
            [homeToCafe, cafeToOffice, officeToNorthwind, northwindToOffice]
        }

        /// Saturday's walk up the hill with Mira, for the journal.
        static let hillWalk: [CLLocationCoordinate2D] = [
            (55.9362, -3.1925), (55.9372, -3.1895), (55.9384, -3.1862), (55.9396, -3.1825),
            (55.9405, -3.1790), (55.9414, -3.1752), (55.9421, -3.1718), (55.9430, -3.1690),
            (55.9436, -3.1660), (55.9441, -3.1618), (55.9450, -3.1598), (55.9462, -3.1590),
            (55.9476, -3.1622), (55.9488, -3.1660), (55.9499, -3.1712), (55.9506, -3.1765),
            (55.9502, -3.1820), (55.9494, -3.1870), (55.9482, -3.1922), (55.9476, -3.1952),
            (55.9460, -3.1958), (55.9440, -3.1952), (55.9415, -3.1940), (55.9390, -3.1922),
            (55.9362, -3.1925),
        ].map { .init(latitude: $0.0, longitude: $0.1) }

        // MARK: Where the time went

        /// A place and the hours spent there over a range.
        struct Spot: Identifiable {
            var id: String { place.id }
            let place: LifePlace
            let hours: Double
            var visits = 0
        }

        static let week: [Spot] = [
            Spot(place: home, hours: 41, visits: 7), Spot(place: office, hours: 31, visits: 5),
            Spot(place: gym, hours: 6, visits: 4), Spot(place: cafe, hours: 4.5, visits: 5),
            Spot(place: leo, hours: 4, visits: 1), Spot(place: meadows, hours: 3, visits: 3),
            Spot(place: mira, hours: 3, visits: 2), Spot(place: hill, hours: 2, visits: 1),
            Spot(place: orrins, hours: 2, visits: 1), Spot(place: northwind, hours: 1.5, visits: 1),
            Spot(place: unknown, hours: 2, visits: 1),
        ]

        static let month: [Spot] = [
            Spot(place: home, hours: 160, visits: 30), Spot(place: office, hours: 118, visits: 19),
            Spot(place: gym, hours: 22, visits: 14), Spot(place: cafe, hours: 15, visits: 17),
            Spot(place: leo, hours: 12, visits: 4), Spot(place: meadows, hours: 11, visits: 10),
            Spot(place: mira, hours: 9, visits: 5), Spot(place: hill, hours: 6, visits: 3),
            Spot(place: orrins, hours: 6, visits: 3), Spot(place: northwind, hours: 5, visits: 3),
            Spot(place: unknown, hours: 4, visits: 2), Spot(place: market, hours: 2, visits: 3),
        ]

        /// The year away from the city, by days.
        static let awayPlaces: [(name: String, lat: Double, lon: Double, days: Double)] = [
            ("London", 51.5072, -0.1276, 9), ("Lisbon", 38.7223, -9.1393, 6),
            ("Skye", 57.2736, -6.2155, 4), ("Glasgow", 55.8642, -4.2518, 3),
            ("Edinburgh", 55.9500, -3.1900, 300),
        ]
    }

    /// One weighted point of heat on a map.
    struct HeatPoint {
        let coordinate: CLLocationCoordinate2D
        /// 0…1, how much time went there against the most.
        let weight: Double
    }

    extension LifeData {
        static func heat(_ spots: [Spot], includingHome: Bool = true) -> [HeatPoint] {
            let counted = spots.filter { includingHome || $0.place.id != "home" }
            let top = counted.map(\.hours).max() ?? 1
            return counted.map {
                HeatPoint(coordinate: $0.place.coordinate, weight: ($0.hours / top).squareRoot())
            }
        }

        static var yearHeat: [HeatPoint] {
            let top = awayPlaces.map(\.days).max() ?? 1
            return awayPlaces.map {
                HeatPoint(
                    coordinate: .init(latitude: $0.lat, longitude: $0.lon),
                    weight: max(0.3, pow($0.days / top, 0.25)))
            }
        }
    }
#endif
