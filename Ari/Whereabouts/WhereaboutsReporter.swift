import AriKit
import CoreLocation
import MapKit
import Observation

/// Where the phone roughly is, for the box: its time zone always, and, once you allow location, its
/// town, for the weather on the Desk and so Kumo follows you when you travel. The fixes come from
/// places' collector, which owns the one location manager: a fix read when Ito opens and an hour or
/// more has passed, and, while places are on, every visit and point of the trail. The town is
/// rounded to about 10 km before it leaves the phone; the box hears only what changed, and once per
/// launch.
@Observable
final class WhereaboutsReporter {
    /// Whether you've allowed location, refused it, or haven't been asked.
    var permission: Permission {
        switch places.access {
        case .notAsked: .notAsked
        case .refused: .refused
        case .allowed: .allowed
        }
    }

    enum Permission: Equatable {
        case notAsked
        case allowed
        /// Refused, or restricted: only the time zone goes.
        case refused
    }

    /// Hands what to send to the session.
    @ObservationIgnored var report: (AriKit.Whereabouts) -> Void = { _ in }

    @ObservationIgnored private let places: PlacesCollector
    @ObservationIgnored private var area: Area?
    @ObservationIgnored private var placeReadAt: Date?
    @ObservationIgnored private var lastSent: AriKit.Whereabouts?
    @ObservationIgnored private var timeZoneObserver: (any NSObjectProtocol)?

    init(places: PlacesCollector) {
        self.places = places
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
        places.heardFix = { [weak self] location in self?.heard(location) }
    }

    /// Ito came on screen: say the time zone, and read the place again if it's been a while.
    func refresh(force: Bool = false) {
        // Turned off in iOS Settings: the place stops going, and the box hears the time zone alone.
        if permission != .allowed { area = nil }
        send()
        guard permission == .allowed else { return }
        let stale = placeReadAt.map { Date.now.timeIntervalSince($0) > 3600 } ?? true
        guard stale || force else { return }
        placeReadAt = nil
        places.readFix()
    }

    /// A new server: it hasn't heard anything yet.
    func reset() {
        lastSent = nil
        send()
    }

    /// You tapped Allow: iOS asks, with Ito's one line on why.
    func ask() {
        places.askWhileUsing()
    }

    private func send() {
        let whereabouts = AriKit.Whereabouts(timeZone: TimeZone.current.identifier, area: area)
        guard whereabouts != lastSent else { return }
        lastSent = whereabouts
        report(whereabouts)
    }

    /// A fix from the collector. Turned off, the place stops going, and the box hears the time
    /// zone alone.
    private func heard(_ location: CLLocation) {
        guard permission == .allowed else {
            if area != nil {
                area = nil
                send()
            }
            return
        }
        // The trail sends a point every few seconds while moving; the town changes rarely.
        if let placeReadAt, Date.now.timeIntervalSince(placeReadAt) < 300 { return }
        Task { await place(location) }
    }

    /// The fix as a town: rounded first, and named only when the rounded place changed.
    private func place(_ location: CLLocation) async {
        placeReadAt = .now
        let rounded = Area(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if let area, area.latitude == rounded.latitude, area.longitude == rounded.longitude {
            return
        }
        let name = await Self.town(at: rounded)
        area = Area(latitude: rounded.latitude, longitude: rounded.longitude, name: name)
        send()
    }

    /// The town at a rounded place, as the phone names it, or none.
    private static func town(at area: Area) async -> String? {
        let location = CLLocation(latitude: area.latitude, longitude: area.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
            let item = try? await request.mapItems.first
        else { return nil }
        return item.addressRepresentations?.cityName
    }
}
