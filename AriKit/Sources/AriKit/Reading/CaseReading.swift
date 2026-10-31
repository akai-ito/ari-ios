import Foundation

/// How a case reads: where it stands, what's happened, newest first, and what's next.
public enum CaseReading {
    /// What's happened, newest first; entries at the same time keep Kumo's order.
    public static func timeline(_ file: CaseFile) -> [CaseFile.Entry] {
        file.timeline.enumerated()
            .sorted { a, b in
                a.element.at.date == b.element.at.date
                    ? a.offset < b.offset : a.element.at.date > b.element.at.date
            }
            .map(\.element)
    }

    /// What the pinned line and In motion say: its status, "Reported to the landlord", then when the
    /// next step is, "Engineer's visit Thu 10:00", or else how long it's waited, "since 15 Oct".
    public static func line(
        _ file: CaseFile, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> (status: String, soon: String?) {
        if let next = file.next, let at = next.at {
            let when = MatterReading.when(
                at, first: false, now: now, calendar: calendar, locale: locale)
            return (file.status, "\(next.text) \(when)")
        }
        let since = file.waitingOn.map {
            "since \(MatterReading.day($0.since, now: now, calendar: calendar, locale: locale))"
        }
        return (file.status, since)
    }
}
