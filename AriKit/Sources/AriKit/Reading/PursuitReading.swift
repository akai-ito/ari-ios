import Foundation

/// How a pursuit reads: how far each option has come through its stages, which is furthest along,
/// and each option's line.
public enum PursuitReading {
    /// Where an option's stage sits in its stages: its index from 0, of how many. `nil` when Kumo
    /// hasn't set the stages out, or the stage isn't one of them. Case and spacing don't matter.
    public static func stage(of option: Pursuit.Option) -> (index: Int, count: Int)? {
        let stage = normalised(option.stage)
        guard let index = option.stages.firstIndex(where: { normalised($0) == stage }) else {
            return nil
        }
        return (index, option.stages.count)
    }

    /// How far an option has come, from 0 to 1: its stage reached, counting the first as one step.
    /// `nil` without stages to measure it by.
    public static func progress(of option: Pursuit.Option) -> Double? {
        stage(of: option).map { Double($0.index + 1) / Double($0.count) }
    }

    /// The options furthest along, by id: more than one when they're level, none when no option
    /// has stages to measure it by.
    public static func leading(in pursuit: Pursuit) -> Set<String> {
        let measured = pursuit.options.compactMap { option in
            progress(of: option).map { (option.id, $0) }
        }
        guard let best = measured.map(\.1).max() else { return [] }
        return Set(measured.filter { $0.1 == best }.map(\.0))
    }

    /// What an option's card says under its name: the next step and who it's with, "Second round ·
    /// Tue 17 Nov · Katia"; otherwise who it's waiting on, "Waiting on them since 18 Sep";
    /// otherwise Kumo's note and who it's with, "Technical done today · Poppy".
    public static func line(
        of option: Pursuit.Option, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        let with = option.people.first.map { " · \($0.name)" } ?? ""
        if let next = option.next {
            return MatterReading.next(next, now: now, calendar: calendar, locale: locale) + with
        }
        if let waiting = option.waitingOn {
            return MatterReading.waiting(waiting, now: now, calendar: calendar, locale: locale)
        }
        return option.note.map { $0 + with }
    }

    /// What the pinned line and In motion say: the option furthest along and its stage, "QRT:
    /// Awaiting answer", and the soonest next step to come, "Citadel Tue 17 Nov" ("Technical Thu
    /// 14:00" when it's the same option's). Each `nil` when there's nothing to say.
    public static func line(
        _ pursuit: Pursuit, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> (detail: String?, soon: String?) {
        let leading = leading(in: pursuit)
        let lead = pursuit.options.first { leading.contains($0.id) } ?? pursuit.options.first
        let today = calendar.startOfDay(for: now)
        let upcoming = pursuit.options.compactMap { option -> (Pursuit.Option, LocalTime)? in
            guard let at = option.next?.at, at.date(in: calendar) >= today else { return nil }
            return (option, at)
        }
        let soonest = upcoming.min { $0.1.date(in: calendar) < $1.1.date(in: calendar) }
        let soon = soonest.map { option, at in
            let when = MatterReading.when(
                at, first: false, now: now, calendar: calendar, locale: locale)
            // The lead's own next step goes by what it is, as its name is already said.
            let what = option.id == lead?.id ? (option.next?.text ?? option.name) : option.name
            return "\(what) \(when)"
        }
        return (lead.map { "\($0.name): \($0.stage)" }, soon)
    }

    private static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
