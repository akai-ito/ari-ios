import Foundation

/// When the phone keeps live GPS points, the costly part of the trail. Visits and significant
/// changes run all the time once places are on; live points run only while you're moving: from a
/// departure or a significant change until iOS says you're stationary or a visit begins. In Low
/// Power Mode or under 20% battery the trail keeps only the stops.
///
/// A plain value, so the rules are tested without Core Location: the app feeds it what it hears
/// and starts or stops live updates as it says.
public struct TrailRhythm: Sendable, Equatable {
    /// How much of the trail is kept.
    public enum Mode: String, Sendable, Equatable, Codable {
        /// Not allowed, or paused: nothing is collected.
        case off
        /// Visits and significant changes only: Low Power Mode or a low battery.
        case stopsOnly
        /// Visits and significant changes, plus live points while moving.
        case full
    }

    /// What the app hears.
    public enum Signal: Sendable, Equatable {
        /// Whether places may run: Always and Precise allowed, and not paused.
        case allowed(Bool)
        /// The battery: Low Power Mode, and its level from 0 to 1 when known.
        case power(lowPower: Bool, level: Double?)
        /// A visit ended: you've left somewhere.
        case departed
        /// A visit began: you've arrived somewhere.
        case arrived
        /// A significant change, about 500 m. `nearStop` when it's still within the visit you're
        /// in, which is cell-tower noise more often than a walk.
        case significantChange(nearStop: Bool)
        /// Live updates said the phone is stationary.
        case stationary
    }

    /// What the app should do now.
    public enum Change: Sendable, Equatable {
        case startLive
        case stopLive
    }

    /// The battery level under which only stops are kept.
    public static let lowBattery = 0.2

    public private(set) var mode: Mode = .off
    /// Whether live updates should be running now.
    public private(set) var live = false

    private var allowed = false
    private var lowPower = false
    private var level: Double?

    public init() {}

    /// Takes in what the app heard, and says whether live updates start or stop.
    @discardableResult
    public mutating func hear(_ signal: Signal) -> Change? {
        switch signal {
        case .allowed(let on):
            allowed = on
        case .power(let low, let level):
            lowPower = low
            self.level = level
        case .departed, .significantChange(nearStop: false):
            guard mode == .full, !live else { return nil }
            live = true
            return .startLive
        case .significantChange(nearStop: true):
            return nil
        case .arrived, .stationary:
            return stop()
        }
        mode = Self.mode(allowed: allowed, lowPower: lowPower, level: level)
        // A change of mode never starts the GPS by itself: the next sign of moving does.
        return mode == .full ? nil : stop()
    }

    private mutating func stop() -> Change? {
        guard live else { return nil }
        live = false
        return .stopLive
    }

    private static func mode(allowed: Bool, lowPower: Bool, level: Double?) -> Mode {
        guard allowed else { return .off }
        if lowPower { return .stopsOnly }
        if let level, level >= 0, level < lowBattery { return .stopsOnly }
        return .full
    }
}

/// Which live points are kept: about one every 10 seconds and 20 metres, and none with a fix worse
/// than 100 m. Live updates arrive about once a second; most of them say nothing new.
public struct TrailThinner: Sendable {
    public static let interval: TimeInterval = 10
    public static let distance: Double = 20
    public static let worstAccuracy: Double = 100

    private var last: TrailPoint?

    public init() {}

    /// Whether to keep `point`; a kept point becomes the one the next is measured from.
    public mutating func keep(_ point: TrailPoint) -> Bool {
        guard point.accuracy > 0, point.accuracy <= Self.worstAccuracy else { return false }
        if let last {
            guard point.at.timeIntervalSince(last.at) >= Self.interval,
                point.metres(from: last) >= Self.distance
            else { return false }
        }
        last = point
        return true
    }

    /// Live updates stopped: the next run starts afresh.
    public mutating func reset() {
        last = nil
    }
}
