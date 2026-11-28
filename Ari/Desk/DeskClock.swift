import Foundation

/// Now, as the Desk tells the time. In debug builds `ARI_CLOCK`, such as `07:40`, sets the time of
/// day the Desk shows, for stills of the morning, the evening or the night; time runs on from there.
nonisolated enum DeskClock {
    static func now(_ date: Date = .now) -> Date {
        #if DEBUG
            if let offset { return date.addingTimeInterval(offset) }
        #endif
        return date
    }

    #if DEBUG
        private static let offset: TimeInterval? = {
            guard let value = ProcessInfo.processInfo.environment["ARI_CLOCK"] else { return nil }
            let parts = value.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2,
                let target = Calendar.current.date(
                    bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
            else { return nil }
            return target.timeIntervalSinceNow
        }()
    #endif
}
