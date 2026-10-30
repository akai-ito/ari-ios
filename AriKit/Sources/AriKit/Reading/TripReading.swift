import Foundation

/// How a trip reads: its line, what's left, its days and the way between stops. Your ticks, in the
/// thing's state, win over how Ari wrote an item.
public enum TripReading {
    /// The to-do list's name in the state.
    public static let todoList = "todo"

    /// Whether a to-do is done: your tick if you've made one, otherwise how Ari wrote it.
    public static func isDone(_ todo: Trip.Todo, in state: MotionState) -> Bool {
        state[todoList]?[todo.id]?.done ?? todo.done
    }

    /// What's left on the to-do list, in its order.
    public static func left(_ trip: Trip, state: MotionState) -> [Trip.Todo] {
        trip.todo.filter { !isDone($0, in: state) }
    }

    /// How much of the to-do list is done, from 0 to 1; `nil` without one.
    public static func progress(_ trip: Trip, state: MotionState) -> Double? {
        guard !trip.todo.isEmpty else { return nil }
        return Double(trip.todo.count - left(trip, state: state).count) / Double(trip.todo.count)
    }

    /// An item's booking as it stands: booked once a to-do about it is done, even before Ari has
    /// heard of your tick and written it in.
    public static func booking(
        _ booking: Trip.Booking?, of item: String, in trip: Trip, state: MotionState
    ) -> Trip.Booking? {
        guard let booking, booking.status == .toBook, ticked(item, in: trip, state: state) else {
            return booking
        }
        return Trip.Booking(status: .booked, ref: booking.ref, url: booking.url)
    }

    /// Where a place stands: booked once a to-do about it is done, and in the plan once a stop in
    /// the days goes there, whatever Ari last called it.
    public static func status(of place: Trip.Place, in trip: Trip, state: MotionState)
        -> PlaceStatus
    {
        if place.status == .booked || ticked(place.id, in: trip, state: state) { return .booked }
        if place.status == .shortlisted, isPlanned(place.id, in: trip) { return .picked }
        return place.status
    }

    /// Whether a stop in the days goes to the place.
    public static func isPlanned(_ place: String, in trip: Trip) -> Bool {
        trip.days.contains { $0.stops.contains { $0.place == place } }
    }

    /// The stops that go to a place, with their days: where it sits in the plan.
    public static func stops(at place: String, in trip: Trip) -> [(day: Trip.Day, stop: Trip.Stop)]
    {
        trip.days.flatMap { day in day.stops.filter { $0.place == place }.map { (day, $0) } }
    }

    /// One row of the Places tab: the places for one kind of thing to do.
    public struct PlaceRow: Sendable, Equatable, Identifiable {
        public let title: String
        public let places: [Trip.Place]

        public var id: String { title }
    }

    /// The places by what you'd do there (Eat, See, Do, then anything else), each row with the
    /// ideas still to decide on first, then what's in the plan, then what's booked.
    public static func placeRows(_ trip: Trip, state: MotionState) -> [PlaceRow] {
        let kinds: [(title: String, categories: [PlaceCategory])] = [
            ("Eat", [.restaurant, .cafe, .bar]),
            ("See", [.museum, .sight, .park]),
            ("Do", [.activity, .shop]),
        ]
        func rank(_ place: Trip.Place) -> Int {
            switch status(of: place, in: trip, state: state) {
            case .shortlisted: 0
            case .picked: 1
            case .booked: 2
            default: 3
            }
        }
        func row(_ title: String, _ places: [Trip.Place]) -> PlaceRow? {
            guard !places.isEmpty else { return nil }
            let ordered = places.enumerated().sorted {
                (rank($0.element), $0.offset) < (rank($1.element), $1.offset)
            }
            return PlaceRow(title: title, places: ordered.map(\.element))
        }
        let known = kinds.flatMap(\.categories)
        return kinds.compactMap { kind in
            row(kind.title, trip.places.filter { kind.categories.contains($0.category) })
        } + [row("Other", trip.places.filter { !known.contains($0.category) })].compactMap(\.self)
    }

    private static func ticked(_ item: String, in trip: Trip, state: MotionState) -> Bool {
        trip.todo.contains { $0.about.contains(item) && isDone($0, in: state) }
    }

    /// What the pinned line and In motion say: "Florence", "6–9 Nov", and how many to-dos are left,
    /// counting your ticks, so the number moves the moment you tick. `nil` without a to-do list.
    public static func line(_ trip: Trip, state: MotionState, locale: Locale = .current) -> (
        name: String, when: String, left: Int?
    ) {
        (
            trip.destination, dates(trip.dates, locale: locale),
            trip.todo.isEmpty ? nil : left(trip, state: state).count
        )
    }

    /// The count in words: "3 to do", or "All done" once nothing's left.
    public static func leftText(_ count: Int) -> String {
        count == 0 ? "All done" : "\(count) to do"
    }

    /// The dates, short: "6–9 Nov", "30 Oct – 2 Nov", or "6 Nov" for a day.
    public static func dates(_ dates: Trip.Dates, locale: Locale = .current) -> String {
        guard let start = day(dates.start), let end = day(dates.end) else {
            return "\(dates.start) – \(dates.end)"
        }
        let calendar = Self.calendar
        let month = format("MMM", locale: locale)
        if start == end {
            return "\(calendar.component(.day, from: start)) \(month.string(from: start))"
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return
                "\(calendar.component(.day, from: start))–\(calendar.component(.day, from: end)) "
                + month.string(from: end)
        }
        return "\(calendar.component(.day, from: start)) \(month.string(from: start)) – "
            + "\(calendar.component(.day, from: end)) \(month.string(from: end))"
    }

    /// The dates in full, with who's going: "Fri 6 – Mon 9 November · You and Janki".
    public static func subtitle(_ trip: Trip, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let start = day(trip.dates.start), let end = day(trip.dates.end) {
            let weekday = format("EEE", locale: locale)
            let month = format("MMMM", locale: locale)
            let calendar = Self.calendar
            let first = "\(weekday.string(from: start)) \(calendar.component(.day, from: start))"
            let last = "\(weekday.string(from: end)) \(calendar.component(.day, from: end))"
            parts.append(
                start == end
                    ? "\(first) \(month.string(from: start))"
                    : calendar.isDate(start, equalTo: end, toGranularity: .month)
                        ? "\(first) – \(last) \(month.string(from: end))"
                        : "\(first) \(month.string(from: start)) – \(last) \(month.string(from: end))"
            )
        }
        if !trip.who.isEmpty {
            parts.append("You and " + ListFormatter.localizedString(byJoining: trip.who))
        }
        return parts.joined(separator: " · ")
    }

    /// A day's heading, such as "Friday 6 November".
    public static func heading(of day: Trip.Day, locale: Locale = .current) -> String {
        guard let date = Self.day(day.date) else { return day.date }
        return format("EEEE d MMMM", locale: locale).string(from: date)
    }

    /// A day's short name, for the map's chips: "Fri".
    public static func shortName(of day: Trip.Day, locale: Locale = .current) -> String {
        guard let date = Self.day(day.date) else { return day.date }
        return format("EEE", locale: locale).string(from: date)
    }

    /// The day to open on: today while the trip is on, otherwise its first day.
    public static func openingDay(of trip: Trip, now: Date = .now) -> Trip.Day? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: trip.timezone) ?? .current
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let text = String(
            format: "%04d-%02d-%02d", today.year ?? 0, today.month ?? 0, today.day ?? 0)
        return trip.days.first { $0.date == text } ?? trip.days.first
    }

    /// Getting to the next stop, in words: "6 min walk", "25 min by tram", "1 h by train · Firenze
    /// SMN → Pisa Centrale".
    public static func move(_ move: Trip.Move) -> String {
        let time = move.minutes.map(duration)
        var text: String
        switch (move.mode, time) {
        case (.walk, let time?): text = "\(time) walk"
        case (.walk, nil): text = "Walk"
        case (let mode, let time?): text = "\(time) by \(name(of: mode))"
        case (let mode, nil): text = "By \(name(of: mode))"
        }
        if let detail = move.detail { text += " · \(detail)" }
        return text
    }

    /// A length of time: "25 min", "1 h", "1 h 20 min".
    public static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// A way of travelling, as a word: "train", "flight".
    public static func name(of mode: TravelMode) -> String {
        switch mode {
        case .flight: "plane"
        case .metro: "metro"
        default: mode.isKnown ? mode.rawValue : "transport"
        }
    }

    /// A local date and time, as said: "Sun 8 Nov, 09:12".
    public static func when(_ local: String, locale: Locale = .current) -> String {
        let parts = local.split(separator: "T").map(String.init)
        guard let date = day(parts[0]) else { return local }
        let text = format("EEE d MMM", locale: locale).string(from: date)
        return parts.count > 1 ? "\(text), \(parts[1])" : text
    }

    /// Where a stop is, from its place.
    public static func place(of stop: Trip.Stop, in trip: Trip) -> Trip.Place? {
        stop.place.flatMap { id in trip.places.first { $0.id == id } }
    }

    /// A stop on the map: its number through the whole trip, its day and where it is.
    public struct MapStop: Sendable, Equatable, Identifiable {
        public let number: Int
        public let day: String
        public let stop: Trip.Stop
        public let location: Trip.Location

        public var id: String { stop.id }
    }

    /// Every stop with somewhere on the map, numbered in order through the trip.
    public static func mapStops(_ trip: Trip) -> [MapStop] {
        var stops: [MapStop] = []
        for day in trip.days {
            for stop in day.stops {
                guard let location = place(of: stop, in: trip)?.location else { continue }
                stops.append(
                    MapStop(number: stops.count + 1, day: day.id, stop: stop, location: location))
            }
        }
        return stops
    }

    // MARK: - Dates

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A day, as noon UTC, so no time zone moves it to the day before.
    private static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text + " 12:00")
    }

    private static func format(_ template: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
