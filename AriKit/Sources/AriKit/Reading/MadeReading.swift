import Foundation

/// How a page Kumo made reads: how far along your ticks are, how a section's items stand, what
/// changed last, and the page as plain text to share.
public enum MadeReading {
    /// The items you can tick, in order: none when the page has no `check` word.
    public static func tickable(_ content: MadeContent) -> [MadeItem] {
        content.check == nil ? [] : content.sections.flatMap(\.items)
    }

    /// How many items are ticked, of how many; `nil` when nothing on the page ticks.
    public static func progress(_ content: MadeContent, state: MadeState) -> (done: Int, of: Int)? {
        let items = tickable(content)
        guard !items.isEmpty else { return nil }
        return (items.filter { state.ticks[$0.id] != nil }.count, items.count)
    }

    /// A section's ticked items, of how many, for its line; `nil` when it has none to tick.
    public static func progress(of section: MadeSection, in content: MadeContent, state: MadeState)
        -> (done: Int, of: Int)?
    {
        guard content.check != nil, !section.items.isEmpty else { return nil }
        return (section.items.filter { state.ticks[$0.id] != nil }.count, section.items.count)
    }

    /// "3 of 9 spotted", from the page's own word.
    public static func progressLine(_ content: MadeContent, state: MadeState) -> String? {
        guard let word = content.check, let progress = progress(content, state: state) else {
            return nil
        }
        return "\(progress.done) of \(progress.of) \(word.lowercased())"
    }

    /// The question on an unticked item: "Spotted it?".
    public static func ask(_ content: MadeContent) -> String {
        "\(content.check ?? "Done") it?"
    }

    /// The latest change worth showing as "Updated": none for a page Kumo hasn't changed since it
    /// made it.
    public static func latestChange(_ detail: MadeDetail) -> MadeChange? {
        guard detail.made.version > 1 else { return nil }
        return detail.changes.max { $0.version < $1.version }
    }

    /// Where a page's sections start, open: the first numbered one, the way you'd walk in.
    public static func openAtFirst(_ content: MadeContent) -> Set<String> {
        content.sections.first(where: \.numbered).map { [$0.id] } ?? []
    }

    /// The page as plain text, to share: its title and summary, each part with what's ticked, and
    /// the credits for its pictures. Blocks inside its words are left out, as when spoken.
    public static func shareText(_ detail: MadeDetail) -> String {
        let content = detail.content
        var lines = [detail.made.title]
        if !detail.made.summary.isEmpty { lines.append(detail.made.summary) }
        if let intro = content.intro.map(plain), !intro.isEmpty { lines += ["", intro] }
        var number = 0
        for section in content.sections {
            lines.append("")
            if section.numbered {
                number += 1
                lines.append(
                    "\(number). \(section.title)" + (section.detail.map { " (\($0))" } ?? ""))
            } else {
                lines.append(section.title.uppercased())
            }
            if let text = section.text.map(plain), !text.isEmpty { lines.append(text) }
            for item in section.items {
                let mark =
                    content.check == nil
                    ? "-" : (detail.state.ticks[item.id] == nil ? "[ ]" : "[x]")
                lines.append("\(mark) \(item.title)" + (item.detail.map { ": \($0)" } ?? ""))
            }
        }
        let credits = Array(
            Set(pictures(detail).map { "\($0.credit), \($0.sourceURL.absoluteString)" })
        ).sorted()
        if !credits.isEmpty { lines += ["", "Pictures: " + credits.joined(separator: "; ")] }
        return lines.joined(separator: "\n")
    }

    /// Every picture the page shows, the cover first.
    public static func pictures(_ detail: MadeDetail) -> [Photo] {
        [detail.made.cover].compactMap(\.self)
            + detail.content.sections.flatMap { section in
                [section.image].compactMap(\.self) + section.items.compactMap(\.image)
            }
    }

    private static func plain(_ markdown: String) -> String {
        ReplyDocument(markdown: markdown).withoutShapes.plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The Made shelf

    /// Something on the Made shelf: a page Kumo made, or a file it showed you for review.
    public enum ShelfItem: Sendable, Equatable, Identifiable {
        case page(Made)
        case document(ShownFile)

        public var id: String {
            switch self {
            case .page(let page): "page \(page.id.rawValue)"
            case .document(let file): "document \(file.id.rawValue)"
            }
        }

        /// When it was made: a page's making, a document's first version.
        public var madeAt: Date {
            switch self {
            case .page(let page): page.madeAt.date
            case .document(let file): file.versions.first?.madeAt.date ?? .distantPast
            }
        }
    }

    /// One stretch of time on the shelf, such as "This week".
    public struct ShelfGroup: Sendable, Equatable, Identifiable {
        public let title: String
        public let items: [ShelfItem]

        public var id: String { title }
    }

    /// The shelf by when each thing was made, newest first: "This week", then "Earlier in
    /// November", then each month before, with its year once it's another year's.
    public static func shelf(
        pages: [Made], documents: [ShownFile], now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [ShelfGroup] {
        let items = (pages.map(ShelfItem.page) + documents.map(ShelfItem.document))
            .sorted { $0.madeAt > $1.madeAt }
        var groups: [ShelfGroup] = []
        for item in items {
            let title = shelfTitle(of: item.madeAt, now: now, calendar: calendar, locale: locale)
            if groups.last?.title == title {
                groups[groups.count - 1] = ShelfGroup(
                    title: title, items: groups[groups.count - 1].items + [item])
            } else {
                groups.append(ShelfGroup(title: title, items: [item]))
            }
        }
        return groups
    }

    private static func shelfTitle(of date: Date, now: Date, calendar: Calendar, locale: Locale)
        -> String
    {
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "This week" }
        let month = DateFormatter()
        month.locale = locale
        month.calendar = calendar
        month.timeZone = calendar.timeZone
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            month.setLocalizedDateFormatFromTemplate("MMMM")
            return "Earlier in \(month.string(from: date))"
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        month.setLocalizedDateFormatFromTemplate(sameYear ? "MMMM" : "MMMM y")
        return month.string(from: date)
    }

    /// When it was made, as the shelf says it: "Today", "Tuesday" within the week, or "9 Nov".
    public static func shelfDay(
        _ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let thisWeek = calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        formatter.setLocalizedDateFormatFromTemplate(thisWeek ? "EEEE" : "d MMM")
        return formatter.string(from: date)
    }
}

/// A name in a reply linked to what Kumo keeps: a page in memory (`memory:people/maya-lind`), a
/// thing in motion (`motion:lisbon-weekend`) or a page Kumo made (`made:va-guide`). Tapping one
/// opens a small card about it.
public enum NameLink: Hashable, Sendable, Identifiable {
    case memory(PageAddress)
    case motion(MotionID)
    case made(MadeID)

    /// Reads a link; `nil` for anything else, such as the web.
    public init?(_ url: URL) {
        let text = url.absoluteString
        if text.hasPrefix("memory:"), text.count > 7 {
            self = .memory(PageAddress(text))
        } else if text.hasPrefix("motion:"), text.count > 7 {
            self = .motion(MotionID(String(text.dropFirst(7))))
        } else if text.hasPrefix("made:"), text.count > 5 {
            self = .made(MadeID(String(text.dropFirst(5))))
        } else {
            return nil
        }
    }

    public var id: String {
        switch self {
        case .memory(let address): address.rawValue
        case .motion(let motion): "motion:\(motion.rawValue)"
        case .made(let made): "made:\(made.rawValue)"
        }
    }

    /// Whether a link's scheme is one of these, for a dotted underline.
    public static func isName(_ url: URL) -> Bool {
        ["memory", "motion", "made"].contains(url.scheme ?? "")
    }
}
