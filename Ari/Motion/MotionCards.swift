import AriKit
import SwiftUI

/// The loudest thing in a section, big, drawn for its kind: a role's pipeline, a block's week, a
/// trip's bookings, a project's parts. Until its content is here, or for a kind Ari doesn't know,
/// it's its title and Kumo's line.
struct MotionLead: View {
    let motion: Motion
    let detail: MotionDetail?
    let space: Namespace.ID?

    @Environment(\.motionOpener) private var opener

    var body: some View {
        let source = "lead \(motion.id)"
        Button {
            opener.open?(motion.id, source)
        } label: {
            Group {
                switch detail?.content {
                case .career(let career)?: CareerLead(motion: motion, career: career)
                case .body(let block)?:
                    BodyLead(motion: motion, block: block, state: detail?.state ?? [:])
                case .trip(let trip)?:
                    TripLead(motion: motion, trip: trip, state: detail?.state ?? [:])
                case .project(let project)?: PartsLead(motion: motion, parts: project.parts)
                case .learning(let learning)?:
                    PartsLead(motion: motion, parts: learning.steps, habit: learning.habit)
                case .other(let other)?:
                    OtherLead(motion: motion, other: other, state: detail?.state ?? [:])
                default: PlainLead(motion: motion, detail: detail)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motionSource(source, in: space)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }
}

/// Anything in a section that isn't the loudest: its name, Kumo's line, and for a role, its
/// pipeline small.
struct MotionRow: View {
    let motion: Motion
    let detail: MotionDetail?
    let space: Namespace.ID?
    var source = "row"

    @Environment(\.motionOpener) private var opener

    var body: some View {
        let source = "\(source) \(motion.id)"
        Button {
            opener.open?(motion.id, source)
        } label: {
            Group {
                if case .career(let career)? = detail?.content {
                    RoleRow(motion: motion, career: career)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(motion.title).font(.headline).foregroundStyle(.ariText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if motion.salience == .quiet {
                                Text("quiet").font(.caption).foregroundStyle(.ariTertiary)
                            }
                        }
                        Text(motion.summary).font(.subheadline).foregroundStyle(.ariSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motionSource(source, in: space)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }
}

/// A big card's title, in the serif.
private struct LeadTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .serif).weight(.semibold))
            .foregroundStyle(.ariText)
            .lineLimit(2)
    }
}

/// For a kind with no shape of its own here: its title and Kumo's line.
private struct PlainLead: View {
    let motion: Motion
    let detail: MotionDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LeadTitle(text: motion.title)
            Text(MotionLineText(motion, detail).detail)
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
        }
    }
}

// MARK: - Career

private struct CareerLead: View {
    let motion: Motion
    let career: Career

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                LeadTitle(text: career.org)
                Spacer()
                if let at = career.next?.at {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(CareerReading.day(at)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ariBone)
                        Text(CareerReading.countdown(to: at)).font(.caption).foregroundStyle(
                            .ariTertiary)
                    }
                }
            }
            Pipeline(
                stage: CareerReading.position(of: career), node: 10, line: 2.5,
                labels: ["lead", "talking", "interviewing", "offer"]
            )
            .padding(.vertical, 2)
            Text(motion.summary).font(.subheadline).foregroundStyle(.ariSecondary)
        }
    }
}

private struct RoleRow: View {
    let motion: Motion
    let career: Career

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(career.org)
                    .font(.headline)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)
                Pipeline(stage: CareerReading.position(of: career), node: 6.5, line: 1.5)
                    .frame(width: 104)
                Spacer(minLength: 8)
                if let at = career.next?.at {
                    Text(when(at)).font(.subheadline.weight(.semibold)).foregroundStyle(.ariText)
                        .lineLimit(1)
                } else if career.waitingOn != nil {
                    Text("waiting").font(.subheadline).foregroundStyle(.ariTertiary)
                }
            }
            Text(motion.summary).font(.subheadline).foregroundStyle(.ariSecondary).lineLimit(2)
        }
    }

    private func when(_ at: LocalTime) -> String {
        [
            CareerReading.day(at).split(separator: " ").first.map(String.init),
            CareerReading.time(at),
        ]
        .compactMap(\.self).joined(separator: " ")
    }
}

// MARK: - Body

private struct BodyLead: View {
    let motion: Motion
    let block: BodyBlock
    let state: MotionState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                LeadTitle(text: motion.title)
                Spacer()
                if let week = BodyReading.currentWeek(of: block)?.week {
                    Text(BodyReading.doneLine(week, state: state))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.ariSecondary)
                }
            }
            if let week = BodyReading.currentWeek(of: block)?.week {
                WeekStrip(days: BodyReading.strip(week, in: block, state: state), barHeight: 44)
            }
            if let next = BodyReading.next(in: block, state: state) {
                Hairline()
                let isToday = BodyReading.today(in: block, state: state) != nil
                HStack(spacing: 10) {
                    if isToday {
                        StatusChip(text: "Today", filled: true)
                    } else {
                        Text("NEXT").font(.caption2.weight(.bold)).kerning(0.8)
                            .foregroundStyle(.ariTertiary)
                    }
                    Text(sessionLine(next, today: isToday))
                        .font(.subheadline)
                        .foregroundStyle(.ariText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
                }
            }
        }
    }

    /// "Easy run · 35 min easy", with its day when it isn't today.
    private func sessionLine(_ session: BodyBlock.Session, today: Bool) -> String {
        var parts = [session.title]
        if !today, let date = BodyReading.noon(session.date.rawValue) {
            parts.append(date.formatted(.dateTime.weekday(.abbreviated)))
        }
        if let plan = BodyReading.plan(of: session) { parts.append(plan) }
        return parts.joined(separator: " · ")
    }
}

/// A week as a coach draws it: a bar a day, as tall as the session is long. Done is solid,
/// planned is printed in dots, and moved is a dashed ghost where it was.
struct WeekStrip: View {
    let days: [BodyReading.Day]
    var barHeight: CGFloat = 44
    var letters = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                DayColumn(day: day, barHeight: barHeight, letters: letters)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        days.flatMap { day in
            day.sessions.filter { $0.mark != .moved }.map { cell in
                "\(cell.session.title), \(cell.mark == .done ? "done" : cell.mark == .letGo ? "let go" : "planned")"
            }
        }.joined(separator: ", ")
    }
}

private struct DayColumn: View {
    let day: BodyReading.Day
    let barHeight: CGFloat
    let letters: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                Color.clear
                if day.sessions.isEmpty {
                    Circle().fill(.ariLine).frame(width: 4, height: 4).padding(.bottom, 2)
                } else {
                    VStack(spacing: 3) {
                        ForEach(day.sessions) { cell in
                            VStack(spacing: 4) {
                                Image(
                                    systemName: cell.mark == .moved
                                        ? "arrow.turn.up.right"
                                        : SessionSymbol.name(cell.session.kind)
                                )
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(cell.mark == .moved ? Color.ariTertiary : .ariBone)
                                SessionBar(mark: cell.mark)
                                    .frame(height: height(cell, count: day.sessions.count))
                            }
                        }
                    }
                }
            }
            .frame(height: barHeight + 16)
            Text(minutes ?? " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(onlyMoved ? Color.ariTertiary.opacity(0.6) : .ariSecondary)
                .strikethrough(onlyMoved, color: .ariTertiary)
            if letters {
                Text(day.letter)
                    .font(.caption2.weight(day.isToday ? .bold : .medium))
                    .foregroundStyle(day.isToday ? Color.ariBone : .ariTertiary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ariField)
            }
        }
    }

    private var onlyMoved: Bool {
        !day.sessions.isEmpty && day.sessions.allSatisfy { $0.mark == .moved }
    }

    private var minutes: String? {
        let known = day.sessions.compactMap(\.minutes)
        return known.isEmpty ? nil : "\(Int(known.reduce(0, +).rounded()))"
    }

    private func height(_ cell: BodyReading.Cell, count: Int) -> CGFloat {
        let share = barHeight / CGFloat(max(1, count))
        return share * max(0.4, min(1, (cell.minutes ?? 30) / 60))
    }
}

/// A session's bar: solid when done, dotted when planned, dashed when moved or let go.
struct SessionBar: View {
    let mark: BodyReading.Mark

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            switch mark {
            case .done:
                shape.fill(.ariBone)
            case .planned:
                DotFill(step: 3.2, size: 0.3).clipShape(shape)
                    .overlay(shape.strokeBorder(Color.ariBone.opacity(0.55), lineWidth: 1))
            case .moved, .letGo:
                shape.strokeBorder(
                    Color.ariTertiary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .padding(.horizontal, 7)
    }
}

/// The symbol for a kind of session: a runner for a run, a dumbbell for a lift.
enum SessionSymbol {
    static func name(_ kind: BodyBlock.Session.Kind) -> String {
        switch kind.plain {
        case .run, .race: "figure.run"
        case .lift: "dumbbell.fill"
        case .ride: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .walk: "figure.walk"
        case .climb: "figure.climbing"
        case .mobility: "figure.flexibility"
        case .sport: "sportscourt.fill"
        case .rest: "moon.zzz.fill"
        default: "figure.mixed.cardio"
        }
    }
}

// MARK: - Trips

private struct TripLead: View {
    let motion: Motion
    let trip: Trip
    let state: MotionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                LeadTitle(text: trip.destination)
                Spacer()
                if let start = LocalTime(trip.dates.start) {
                    Text(CareerReading.countdown(to: start)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariBone)
                }
            }
            Text(TripReading.subtitle(trip))
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .padding(.top, -6)
            TripSkeleton(trip: trip, state: state, compact: true).padding(.vertical, 2)
            if let next = TripReading.left(trip, state: state).first {
                Hairline()
                HStack(spacing: 10) {
                    Text("NEXT").font(.caption2.weight(.bold)).kerning(0.8)
                        .foregroundStyle(.ariTertiary)
                    Text(next.text).font(.subheadline).foregroundStyle(.ariText).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
                }
            }
        }
    }
}

/// A trip's skeleton: its bookings laid on the days, the stay as a bar through them. Booked is
/// solid; still to book is printed in dots, with a dashed ring.
struct TripSkeleton: View {
    let trip: Trip
    let state: MotionState
    var compact = false

    private struct Moment: Identifiable {
        let id: String
        let hours: Double
        let symbol: String
        let booked: Bool
        let label: String
    }

    private var days: [String] {
        guard let count = dayCount else { return [] }
        return (0..<count).map { BodyReading.adding($0, to: trip.dates.start) }
    }

    private var dayCount: Int? {
        guard let start = BodyReading.noon(trip.dates.start),
            let end = BodyReading.noon(trip.dates.end)
        else { return nil }
        let days = Int((end.timeIntervalSince(start) / 86_400).rounded()) + 1
        return (1...14).contains(days) ? days : nil
    }

    /// Hours from the first day's midnight to a local date and time, or a day's noon.
    private func hours(_ local: String?) -> Double? {
        guard let local, let start = BodyReading.noon(trip.dates.start) else { return nil }
        let parts = local.split(separator: "T").map(String.init)
        guard let day = BodyReading.noon(parts[0]) else { return nil }
        let clock =
            parts.count > 1 ? parts[1].split(separator: ":").compactMap { Double($0) } : [12, 0]
        guard clock.count == 2 else { return nil }
        return day.timeIntervalSince(start) / 3600 + clock[0] + clock[1] / 60
    }

    private var moments: [Moment] {
        let legs = trip.travel.compactMap { leg -> Moment? in
            guard let at = hours(leg.depart),
                let booking = TripReading.booking(leg.booking, of: leg.id, in: trip, state: state),
                booking.status == .booked || booking.status == .toBook
            else { return nil }
            return Moment(
                id: leg.id, hours: at, symbol: MotionSymbol.name(for: leg.mode),
                booked: booking.status == .booked,
                label: leg.depart?.split(separator: "T").last.map(String.init) ?? "")
        }
        let stops = trip.days.flatMap { day in
            day.stops.compactMap { stop -> Moment? in
                guard
                    let booking = TripReading.booking(
                        stop.booking, of: stop.id, in: trip, state: state),
                    booking.status == .booked || booking.status == .toBook,
                    let at = hours(stop.time.map { "\(day.date)T\($0)" } ?? day.date)
                else { return nil }
                let place = TripReading.place(of: stop, in: trip)
                return Moment(
                    id: stop.id, hours: at,
                    symbol: place.map { MotionSymbol.name(for: $0.category) } ?? "mappin",
                    booked: booking.status == .booked, label: stop.title)
            }
        }
        return (legs + stops).sorted { $0.hours < $1.hours }
    }

    /// The moments whose label has room: none closer than a sixth of a day before it, in its lane.
    private var labelled: Set<String> {
        var last: [Bool: Double] = [:]
        var shown: Set<String> = []
        for moment in moments where (last[moment.booked].map { moment.hours - $0 > 10 } ?? true) {
            shown.insert(moment.id)
            last[moment.booked] = moment.hours
        }
        return shown
    }

    var body: some View {
        if let count = dayCount {
            let span = Double(count) * 24
            let labelled = labelled
            let side: CGFloat = compact ? 18 : 26
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        Text(dayName(day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.ariTertiary)
                            .padding(.leading, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let x = { (hours: Double) in width * min(max(hours, 0), span) / span }
                    ZStack(alignment: .topLeading) {
                        ForEach(1..<count, id: \.self) { day in
                            Rectangle().fill(.ariLine.opacity(0.7))
                                .frame(width: 1, height: geometry.size.height)
                                .offset(x: x(Double(day) * 24))
                        }
                        ForEach(trip.stays) { stay in
                            let from = hours(stay.checkIn) ?? 0
                            let to = hours(stay.checkOut) ?? span
                            Capsule()
                                .fill(stay.booking?.status == .toBook ? Color.ariDusk : .ariBone)
                                .frame(width: max(8, x(to) - x(from)), height: compact ? 6 : 18)
                                .overlay(alignment: .leading) {
                                    if !compact {
                                        Label(stay.name, systemImage: "bed.double.fill")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.ariBackground)
                                            .lineLimit(1)
                                            .padding(.leading, 8)
                                    }
                                }
                                .offset(x: x(from), y: (compact ? 30 : 56) - (compact ? 3 : 9))
                        }
                        ForEach(moments) { moment in
                            VStack(spacing: 3) {
                                TripMoment(symbol: moment.symbol, booked: moment.booked, side: side)
                                if !compact, labelled.contains(moment.id) {
                                    Text(moment.label)
                                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                                        .foregroundStyle(
                                            moment.booked ? Color.ariSecondary : .ariTertiary
                                        )
                                        .lineLimit(1)
                                        .frame(maxWidth: 72)
                                }
                            }
                            .position(
                                x: min(max(x(moment.hours), side / 2), width - side / 2),
                                y: compact ? 9 : (moment.booked ? 13 : 84) + 8)
                        }
                    }
                }
                .frame(height: compact ? 36 : 112)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(moments.filter(\.booked).count) booked, \(moments.filter { !$0.booked }.count) to book"
            )
        }
    }

    private func dayName(_ day: String) -> String {
        guard let date = BodyReading.noon(day) else { return day }
        return compact
            ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

/// One of a trip's bookings on its rail: a solid disc when booked, dots in a dashed ring when it's
/// still to book.
struct TripMoment: View {
    let symbol: String
    let booked: Bool
    var side: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(booked ? Color.ariBackground : .ariBone)
            .frame(width: side, height: side)
            .background {
                if booked {
                    Circle().fill(.ariBone)
                } else {
                    Circle().fill(Color.ariSurface)
                        .overlay(DotFill(step: 2.6, size: 0.26).clipShape(Circle()).opacity(0.45))
                        .overlay(
                            Circle().strokeBorder(
                                Color.ariBone.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Projects, learning and other

private struct PartsLead: View {
    let motion: Motion
    let parts: [MotionPart]
    var habit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(motion.title).font(.headline).foregroundStyle(.ariText).lineLimit(2)
                Spacer()
                if !parts.isEmpty {
                    Text("\(parts.filter { $0.status == .done }.count) of \(parts.count) parts")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.ariSecondary)
                } else if let habit {
                    Text(habit).font(.footnote).foregroundStyle(.ariSecondary)
                }
            }
            if !parts.isEmpty {
                Segments(parts: parts.map(\.status))
            }
            Text(motion.summary).font(.subheadline).foregroundStyle(.ariSecondary)
        }
    }
}

private struct OtherLead: View {
    let motion: Motion
    let other: OtherMatter
    let state: MotionState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(motion.title).font(.headline).foregroundStyle(.ariText)
                Text(motion.summary).font(.subheadline).foregroundStyle(.ariSecondary)
            }
            Spacer(minLength: 8)
            if !other.todo.isEmpty {
                HStack(spacing: 5) {
                    ForEach(other.todo.prefix(6)) { todo in
                        if state[OtherMatter.todoList]?[todo.id]?.done ?? todo.done {
                            Circle().fill(.ariBone).frame(width: 9, height: 9)
                        } else {
                            Circle().strokeBorder(Color.ariBone.opacity(0.6), lineWidth: 1.2)
                                .frame(width: 9, height: 9)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}
