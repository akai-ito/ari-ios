import AriKit
import CoreLocation
import Observation
import UIKit
import os

/// Where you go, kept as a hybrid trail for your box: iOS's visits and significant changes all the
/// time once places are on, and live GPS only while you're moving (see ``TrailRhythm``). Places need
/// Always and Precise Location; with less they stay off and say so, rather than drawing a trail
/// full of gaps.
///
/// Made at launch, because visits and significant changes relaunch Ito in the background: the
/// manager has to exist, with its delegate, for iOS to hand them over. The same manager reads a fix
/// for the town on the Desk, with While Using alone.
@Observable
final class PlacesCollector: NSObject, CLLocationManagerDelegate {
    /// What iOS allows Ito.
    enum Access: Equatable {
        case notAsked
        /// Refused, or restricted: nothing, not even the town.
        case refused
        case allowed(always: Bool, precise: Bool)

        /// Whether places can run: Always, with Precise on.
        var isEnough: Bool { self == .allowed(always: true, precise: true) }
    }

    private(set) var access: Access = .notAsked
    /// You paused places in Settings: nothing is collected until you turn them back on.
    private(set) var paused: Bool
    /// What the trail is keeping now, and whether live GPS is running.
    private(set) var rhythm = TrailRhythm()
    /// Whether iOS's one Always prompt has been used: after that, only iOS Settings can change it.
    private(set) var askedAlways: Bool

    /// Places are on: allowed, and not paused.
    var isOn: Bool { access.isEnough && !paused }

    /// Every fix, for the town and time zone the Desk's weather follows.
    @ObservationIgnored var heardFix: (CLLocation) -> Void = { _ in }

    @ObservationIgnored let uploads: TrailUploads
    @ObservationIgnored let log: LiveLog?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var thinner = TrailThinner()
    @ObservationIgnored private var live: Task<Void, Never>?
    @ObservationIgnored private var activity: CLBackgroundActivitySession?
    /// Live points kept in this run, for the diary.
    @ObservationIgnored private var runPoints = 0
    /// The visit you're in, arrived and not yet left, to tell a walk from cell-tower noise.
    @ObservationIgnored private var stop: TrailVisit?
    /// A fix was asked for: the next update is that, not a significant change.
    @ObservationIgnored private var wantsFix = false
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private static let logger = Logger(subsystem: "io.github.akai-ito.ari", category: "places")

    init(uploads: TrailUploads, log: LiveLog?, defaults: UserDefaults = .standard) {
        self.uploads = uploads
        self.log = log
        self.defaults = defaults
        paused = defaults.bool(forKey: Keys.paused)
        askedAlways = defaults.bool(forKey: Keys.askedAlways)
        super.init()
        // Enough for the town; visits and significant changes don't follow it.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        access = Self.access(manager)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [
            UIDevice.batteryLevelDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.powerChanged() }
                })
        }
        apply(resuming: defaults.bool(forKey: Keys.live))
    }

    // MARK: - What you do

    /// Step one of the ask: While Using, with Precise on in iOS's prompt.
    func askWhileUsing() {
        manager.requestWhenInUseAuthorization()
    }

    /// Step two: iOS offers "Change to Always Allow", once.
    func askAlways() {
        askedAlways = true
        defaults.set(true, forKey: Keys.askedAlways)
        manager.requestAlwaysAuthorization()
    }

    /// Settings' switch: paused, nothing is collected, and live GPS stops at once.
    func setPaused(_ paused: Bool) {
        self.paused = paused
        defaults.set(paused, forKey: Keys.paused)
        note(.mode, paused ? "paused" : "resumed")
        apply()
    }

    /// A fix for the town, when Ito opens and an hour has passed.
    func readFix() {
        guard case .allowed = access else { return }
        wantsFix = true
        manager.requestLocation()
    }

    // MARK: - Turning things on and off

    private func apply(resuming: Bool = false) {
        if isOn {
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringVisits()
            manager.stopMonitoringSignificantLocationChanges()
        }
        follow(rhythm.hear(.allowed(isOn)), because: isOn ? "places on" : "places off")
        powerChanged()
        // iOS ended Ito mid-run: the run carries on.
        if resuming, isOn { follow(rhythm.hear(.departed), because: "relaunched mid-run") }
    }

    private func powerChanged() {
        let before = rhythm.mode
        let change = rhythm.hear(.power(lowPower: Self.lowPower, level: Self.battery))
        if rhythm.mode != before { note(.mode, rhythm.mode.rawValue) }
        follow(change, because: Self.lowPower ? "low power" : "low battery")
    }

    private func follow(_ change: TrailRhythm.Change?, because reason: String) {
        switch change {
        case .startLive: startLive(reason)
        case .stopLive: stopLive(reason)
        case nil: break
        }
    }

    /// Live GPS, in a background activity session so it carries on with Ito closed, until the
    /// rhythm says stop.
    private func startLive(_ reason: String) {
        guard live == nil else { return }
        defaults.set(true, forKey: Keys.live)
        note(.liveOn, reason)
        activity = CLBackgroundActivitySession()
        runPoints = 0
        live = Task { [weak self] in
            var reason = "live updates ended"
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self, !Task.isCancelled else { return }
                    if update.stationary {
                        reason = "stationary"
                        break
                    }
                    if let location = update.location { self.heardLive(location) }
                }
            } catch {
                Self.logger.notice("live updates ended: \(error)")
            }
            // Stationary, or iOS ended the updates: either way the run is over, until the next
            // sign of moving.
            guard let self, !Task.isCancelled else { return }
            self.follow(self.rhythm.hear(.stationary), because: reason)
        }
    }

    private func stopLive(_ reason: String) {
        guard live != nil else { return }
        live?.cancel()
        live = nil
        activity?.invalidate()
        activity = nil
        thinner.reset()
        defaults.set(false, forKey: Keys.live)
        note(.liveOff, "\(reason) · \(runPoints) points")
        Task { await uploads.send() }
    }

    private func heardLive(_ location: CLLocation) {
        let point = Self.point(location, .live)
        guard thinner.keep(point) else { return }
        runPoints += 1
        keep(point)
        heardFix(location)
    }

    private func keep(_ point: TrailPoint) {
        do {
            try uploads.queue.add(point)
        } catch {
            Self.logger.error("couldn't keep a point: \(error)")
        }
        uploads.added()
    }

    private func note(_ kind: LiveLog.Entry.Kind, _ detail: String) {
        Self.logger.info("trail \(kind.rawValue): \(detail)")
        log?.add(
            LiveLog.Entry(
                at: .now, kind: kind, detail: detail, battery: Self.battery,
                lowPower: Self.lowPower))
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let access = Self.access(manager)
        MainActor.assumeIsolated {
            guard access != self.access else { return }
            self.access = access
            apply()
            if case .allowed = access { readFix() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let arrived = visit.arrivalDate == .distantPast ? nil : visit.arrivalDate
        let departed = visit.departureDate == .distantFuture ? nil : visit.departureDate
        // Neither end known says nothing worth keeping.
        guard arrived != nil || departed != nil else { return }
        let kept = TrailVisit(
            arrived: arrived, departed: departed, latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude, accuracy: max(0, visit.horizontalAccuracy))
        MainActor.assumeIsolated { heard(kept) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            // A fix asked for when Ito opened is as precise as a live point.
            let source: TrailPoint.Source = wantsFix ? .live : .change
            wantsFix = false
            for location in locations { heard(location, source) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        // No fix this time: the next visit, change or opening tries again.
        MainActor.assumeIsolated { wantsFix = false }
    }

    private func heard(_ visit: TrailVisit) {
        guard isOn else { return }
        if UIApplication.shared.applicationState == .background {
            note(.woke, visit.departed == nil ? "arrived" : "departed")
        }
        // Kept at once, so it survives whatever iOS does next.
        keep(visit)
        if visit.departed == nil {
            stop = visit
            follow(rhythm.hear(.arrived), because: "arrived")
        } else {
            stop = nil
            follow(rhythm.hear(.departed), because: "departed")
        }
        heardFix(CLLocation(latitude: visit.latitude, longitude: visit.longitude))
        // Named by Apple's map data while there's time, then sent: arriving and leaving are events
        // the box acts on. Woken in the background, iOS gives a few seconds; this asks for them.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Visit")
        Task {
            if let placemark = await Self.name(visit) {
                var named = visit
                named.placemark = placemark
                keep(named)
            }
            await uploads.send()
            UIApplication.shared.endBackgroundTask(background)
        }
    }

    private func keep(_ visit: TrailVisit) {
        do {
            try uploads.queue.add(visit)
        } catch {
            Self.logger.error("couldn't keep a visit: \(error)")
        }
        uploads.added()
    }

    /// Apple's name for a visit's spot, given four seconds at most.
    private static func name(_ visit: TrailVisit) async -> Placemark? {
        await withTaskGroup(of: Placemark?.self) { group in
            group.addTask {
                await Placemarks.name(latitude: visit.latitude, longitude: visit.longitude)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func heard(_ location: CLLocation, _ source: TrailPoint.Source) {
        // A negative accuracy is iOS saying the fix is no good.
        guard location.horizontalAccuracy >= 0 else { return }
        heardFix(location)
        guard isOn else { return }
        keep(Self.point(location, source))
        guard source == .change else { return }
        if UIApplication.shared.applicationState == .background { note(.woke, "change") }
        let nearStop = stop.map {
            TrailPoint.metres(
                $0.latitude, $0.longitude, location.coordinate.latitude,
                location.coordinate.longitude) < max(250, $0.accuracy + location.horizontalAccuracy)
        }
        follow(
            rhythm.hear(.significantChange(nearStop: nearStop ?? false)),
            because: "significant change")
    }

    // MARK: - Reading iOS

    nonisolated private static func access(_ manager: CLLocationManager) -> Access {
        let precise = manager.accuracyAuthorization == .fullAccuracy
        switch manager.authorizationStatus {
        case .notDetermined: return .notAsked
        case .authorizedAlways: return .allowed(always: true, precise: precise)
        case .authorizedWhenInUse: return .allowed(always: false, precise: precise)
        default: return .refused
        }
    }

    private static var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// The battery from 0 to 1, or `nil` where iOS doesn't know, as in the Simulator.
    private static var battery: Double? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
    }

    private static func point(_ location: CLLocation, _ source: TrailPoint.Source) -> TrailPoint {
        TrailPoint(
            at: location.timestamp, latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy,
            altitude: location.verticalAccuracy > 0 ? location.altitude : nil,
            speed: location.speed, course: location.course, source: source)
    }

    private enum Keys {
        static let paused = "placesPaused"
        static let askedAlways = "placesAskedAlways"
        static let live = "trailLiveOn"
    }
}
