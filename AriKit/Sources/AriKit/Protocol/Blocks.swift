import Foundation

/// Where part of a reply does something Markdown can't, Ari writes it as a fenced block, `ari:` and a
/// kind, holding one JSON object, and the app draws it: a place with Directions, short answers to
/// tap, pictures Ari found, a line that opens a thing in motion, picks, a table with verdicts, a
/// number that matters, an event to add, a Desk card, a person, a page Kumo made. A block Ari
/// doesn't know, or whose JSON doesn't read, shows as its fenced text. Everything else in a reply is
/// Markdown.
public enum ReplyShape: Sendable, Equatable {
    case place(Place)
    case choices(Choices)
    case images(Images)
    case motion(MotionLine)
    case picks(Picks)
    case table(Table)
    case number(KeyNumber)
    case event(CalendarEvent)
    case desk(DeskItem)
    case person(Person)
    case made(MadeCard)
    case file(FileCard)
    case proposals(Proposals)

    /// Reads a fenced block's language and text; `nil` if it isn't a shape this Ari knows, or its
    /// JSON doesn't read.
    public init?(language: String?, json: String) {
        guard let kind = language?.split(separator: ":").dropFirst().first,
            language?.hasPrefix("ari:") == true
        else { return nil }
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        do {
            switch kind {
            case "place": self = .place(try decoder.decode(Place.self, from: data))
            case "choices": self = .choices(try decoder.decode(Choices.self, from: data))
            case "images": self = .images(try decoder.decode(Images.self, from: data))
            case "motion": self = .motion(try decoder.decode(MotionLine.self, from: data))
            case "picks": self = .picks(try decoder.decode(Picks.self, from: data))
            case "table": self = .table(try decoder.decode(Table.self, from: data))
            case "number": self = .number(try decoder.decode(KeyNumber.self, from: data))
            case "event": self = .event(try decoder.decode(CalendarEvent.self, from: data))
            case "desk": self = .desk(try decoder.decode(DeskItem.self, from: data))
            case "person": self = .person(try decoder.decode(Person.self, from: data))
            case "made": self = .made(try decoder.decode(MadeCard.self, from: data))
            case "file": self = .file(try decoder.decode(FileCard.self, from: data))
            case "proposals": self = .proposals(try decoder.decode(Proposals.self, from: data))
            default: return nil
            }
        } catch {
            return nil
        }
    }

    /// A place you might go, with Directions: it opens in Maps.
    public struct Place: Sendable, Equatable, Decodable {
        public let name: String
        public let address: String?
        /// What's useful now, such as "open till 17:45".
        public let note: String?
        public let lat: Double?
        public let lon: Double?
        public let url: URL?
        /// A picture of it, small beside its name.
        public let image: Photo?

        public init(
            name: String, address: String? = nil, note: String? = nil, lat: Double? = nil,
            lon: Double? = nil, url: URL? = nil, image: Photo? = nil
        ) {
            self.name = name
            self.address = address
            self.note = note
            self.lat = lat
            self.lon = lon
            self.url = url
            self.image = image
        }

        enum CodingKeys: String, CodingKey { case name, address, note, lat, lon, url, image }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            address = try c.decodeIfPresent(String.self, forKey: .address)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            lat = try c.decodeIfPresent(Double.self, forKey: .lat)
            lon = try c.decodeIfPresent(Double.self, forKey: .lon)
            url = try? c.decodeIfPresent(URL.self, forKey: .url)
            // A picture that doesn't read leaves the place without one, not the reply without it.
            image = try? c.decodeIfPresent(Photo.self, forKey: .image)
        }
    }

    /// Short answers you might give next. A tap sends the label as a message.
    public struct Choices: Sendable, Equatable, Decodable {
        public let options: [String]
    }

    /// A compact line under a reply, when Ari starts or changes a thing in motion: "Florence with
    /// Mira: booked the Uffizi". Tapping it opens the thing.
    public struct MotionLine: Sendable, Equatable, Decodable {
        public let motion: MotionID
        /// The thing's version the line is about; its note says what changed.
        public let change: Int?
    }

    /// Pictures Ari found on the web, kept on the server as attachments. Never generated.
    public struct Images: Sendable, Equatable, Decodable {
        public let images: [Photo]
    }

    /// Ari's decisive picks, in order, each with a picture, a price or time, and one line on why.
    public struct Picks: Sendable, Equatable, Decodable {
        /// A heading over them, such as "What I'd order".
        public let title: String?
        public let picks: [Pick]

        public struct Pick: Sendable, Equatable, Decodable {
            public let name: String
            /// A price or a time, such as "£9.50".
            public let detail: String?
            public let why: String
            public let image: Photo?

            enum CodingKeys: String, CodingKey { case name, detail, why, image }

            public init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                detail = try c.decodeIfPresent(String.self, forKey: .detail)
                why = try c.decode(String.self, forKey: .why)
                image = try? c.decodeIfPresent(Photo.self, forKey: .image)
            }
        }
    }

    /// A table that fits a phone: a row per thing, its name and a line, up to two short values,
    /// and Ari's verdict as a chip.
    public struct Table: Sendable, Equatable, Decodable {
        /// The name's heading, then each value's, then the verdict's.
        public let columns: [String]
        public let rows: [Row]

        public struct Row: Sendable, Equatable, Decodable {
            public let name: String
            public let detail: String?
            public let values: [String]
            public let verdict: Verdict?

            enum CodingKeys: String, CodingKey { case name, detail, values, verdict }

            public init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                detail = try c.decodeIfPresent(String.self, forKey: .detail)
                values = try c.decodeIfPresent([String].self, forKey: .values) ?? []
                verdict = try? c.decodeIfPresent(Verdict.self, forKey: .verdict)
            }
        }
    }

    /// Ari's take on one thing, as a chip: three strengths of bone and a quiet grey.
    public struct Verdict: Sendable, Equatable, Decodable {
        public let label: String
        public let tone: Tone

        public init(label: String, tone: Tone) {
            self.label = label
            self.tone = tone
        }

        /// How strongly it's said. A tone Ari doesn't know reads as `neutral`.
        public struct Tone: OpenValue {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            /// The few best: "Must try".
            public static let strong = Tone(rawValue: "strong")
            /// "Recommended".
            public static let good = Tone(rawValue: "good")
            /// A plain fact: "Best value".
            public static let neutral = Tone(rawValue: "neutral")
            /// A condition or a pass: "If you like heat", "Skip today".
            public static let quiet = Tone(rawValue: "quiet")
            public static let known = [strong, good, neutral, quiet]
        }
    }

    /// A number that matters, with what it is and what it's made of.
    public struct KeyNumber: Sendable, Equatable, Decodable {
        public let label: String
        public let value: String
        public let context: String?
    }

    /// An event Ari suggests, with Add: the phone's own event sheet, filled in.
    public struct CalendarEvent: Sendable, Equatable, Decodable {
        public let title: String
        public let start: Date
        public let end: Date?
        public let allDay: Bool
        public let place: String?
        public let notes: String?
        /// Ari already put it on your calendar.
        public let onCalendar: Bool

        enum CodingKeys: String, CodingKey {
            case title, start, end, place, notes
            case allDay = "all_day"
            case onCalendar = "on_calendar"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            let startText = try c.decode(String.self, forKey: .start)
            guard let start = Self.date(startText) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .start, in: c, debugDescription: "\(startText) is not RFC 3339.")
            }
            self.start = start
            end = try c.decodeIfPresent(String.self, forKey: .end).flatMap(Self.date)
            allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
            place = try c.decodeIfPresent(String.self, forKey: .place)
            notes = try c.decodeIfPresent(String.self, forKey: .notes)
            onCalendar = try c.decodeIfPresent(Bool.self, forKey: .onCalendar) ?? false
        }

        /// RFC 3339 with any offset, with or without fractions of a second.
        static func date(_ text: String) -> Date? {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(text))
        }
    }

    /// A card waiting on the Desk, shown in the chat as the same card: one item, two views.
    public struct DeskItem: Sendable, Equatable, Decodable {
        public let card: CardID
    }

    /// Someone Ari keeps a page about.
    public struct Person: Sendable, Equatable, Decodable {
        public let page: PageAddress
    }

    /// A page Kumo made, as a card that opens it.
    public struct MadeCard: Sendable, Equatable, Decodable {
        public let made: MadeID
    }

    /// A file Ari made or changed, such as a PDF, at one version: a card that opens its pages.
    public struct FileCard: Sendable, Equatable, Decodable {
        public let file: FileID
        public let version: Int
    }

    /// Changes Ari proposes and hasn't made, each its own row with Skip and its own verb. Nothing
    /// happens until you tap one; a tap sends your message with an ``YourTap/decision(_:)``.
    public struct Proposals: Sendable, Equatable, Decodable {
        public let title: String?
        public let items: [Item]

        public struct Item: Sendable, Equatable, Decodable, Identifiable {
            public let id: String
            /// `calendar`, `draft`, `memory`, `desk`, `motion`, `wakeup` or `other`, for its symbol.
            public let kind: String?
            public let title: String
            public let detail: String?
            /// Its button, such as "Add" or "Draft it".
            public let verb: String
            /// What it says once accepted, such as "Added to your calendar".
            public let done: String
        }
    }
}

extension ReplyDocument {
    /// The reply's shapes, by the index of the block that holds each: `nil` for an `ari:` block this
    /// Ari can't read.
    public var shapes: [Int: ReplyShape?] {
        var shapes: [Int: ReplyShape?] = [:]
        for (index, block) in blocks.enumerated() {
            guard case .code(let language) = block.kind, language?.hasPrefix("ari:") == true else {
                continue
            }
            shapes[index] = ReplyShape(language: language, json: block.runs.map(\.text).joined())
        }
        return shapes
    }

    /// The reply without its blocks, as it's said aloud: blocks are never spoken.
    public var withoutShapes: ReplyDocument {
        var document = self
        document.blocks.removeAll { block in
            if case .code(let language) = block.kind {
                language?.hasPrefix("ari:") == true
            } else {
                false
            }
        }
        return document
    }
}
