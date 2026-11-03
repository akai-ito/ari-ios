import AriKit
import CoreLocation
import MapKit
import Observation

/// Where the phone roughly is, for the box: its time zone always, and, once you allow it, its town,
/// for the weather on the Desk and so Kumo follows you when you travel. Location is asked for at
/// reduced accuracy, only while Ito is in use, and rounded to about 10 km before it leaves the
/// phone. It's read when Ito opens and an hour or more has passed, and whenever the time zone
/// changes; the box hears only what changed, and once per launch.
@Observable
final class WhereaboutsReporter: NSObject, CLLocationManagerDelegate {
    /// Whether you've allowed rough location, refused it, or haven't been asked.
    private(set) var permission: Permission = .notAsked

    enum Permission: Equatable {
        case notAsked
        case allowed
        /// Refused, or restricted: only the time zone goes.
        case refused
    }

    /// Hands what to send to the session.
    @ObservationIgnored var report: (AriKit.Whereabouts) -> Void = { _ in }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var area: Area?
    @ObservationIgnored private var placeReadAt: Date?
    @ObservationIgnored private var lastSent: AriKit.Whereabouts?
    @ObservationIgnored private var timeZoneObserver: (any NSObjectProtocol)?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
        permission = Self.permission(manager.authorizationStatus)
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
    }

    /// Ito came on screen: say the time zone, and read the place again if it's been a while.
    func refresh(force: Bool = false) {
        send()
        guard permission == .allowed else { return }
        let stale = placeReadAt.map { Date.now.timeIntervalSince($0) > 3600 } ?? true
        if stale || force { manager.requestLocation() }
    }

    /// A new server: it hasn't heard anything yet.
    func reset() {
        lastSent = nil
        send()
    }

    /// You tapped Allow: iOS asks, with Ito's one line on why.
    func ask() {
        manager.requestWhenInUseAuthorization()
    }

    private func send() {
        let whereabouts = AriKit.Whereabouts(timeZone: TimeZone.current.identifier, area: area)
        guard whereabouts != lastSent else { return }
        lastSent = whereabouts
        report(whereabouts)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            permission = Self.permission(status)
            if permission == .allowed {
                self.manager.requestLocation()
            } else if area != nil {
                // Turned off: the place stops going, and the box hears the time zone alone.
                area = nil
                send()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.place(location) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        // No fix this time: the time zone has gone already, and the place is read next time.
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

    private static func permission(_ status: CLAuthorizationStatus) -> Permission {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .notDetermined: .notAsked
        default: .refused
        }
    }
}
