import Foundation

/// An item in one of a reply's plans, ticked or not.
public struct Tick: Hashable, Sendable, Codable {
    /// The plan's index among the reply's `ari:` blocks, from 0.
    public let part: Int
    /// The item's `id` in the plan.
    public let item: String
    public let done: Bool

    public init(part: Int, item: String, done: Bool) {
        self.part = part
        self.item = item
        self.done = done
    }
}

/// The body of `PUT /v0/messages/{message}/parts/{part}/items/{item}`.
public struct TickItem: Sendable, Equatable, Codable {
    public let done: Bool

    public init(done: Bool) { self.done = done }
}

/// Its answer: the reply's ticks, each at its latest.
public struct TickList: Sendable, Equatable, Codable {
    public let ticks: [Tick]
}

/// `plan.ticked`: an item in a reply's plan was ticked or unticked, on any device.
public struct PlanTicked: Sendable, Equatable, Decodable {
    public let at: Timestamp
    public let message: MessageID
    public let part: Int
    public let item: String
    public let done: Bool
}

/// Where a reply's content has a shape, Ari writes it as a fenced block, `ari:` and a kind, holding
/// one JSON object, and the app draws it. A block Ari doesn't know, or whose JSON doesn't read, shows
/// as its fenced text.
public enum ReplyShape: Sendable, Equatable {
    case plan(Plan)
    case place(Place)
    case time(Time)
    case compare(Compare)
    case choices(Choices)
    case images(Images)
    case motion(MotionLine)

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
            case "plan": self = .plan(try decoder.decode(Plan.self, from: data))
            case "place": self = .place(try decoder.decode(Place.self, from: data))
            case "time": self = .time(try decoder.decode(Time.self, from: data))
            case "compare":
                self = .compare(try decoder.decode(Compare.self, from: data).ordered(as: json))
            case "choices": self = .choices(try decoder.decode(Choices.self, from: data))
            case "images": self = .images(try decoder.decode(Images.self, from: data))
            case "motion": self = .motion(try decoder.decode(MotionLine.self, from: data))
            default: return nil
            }
        } catch {
            return nil
        }
    }

    /// Something to do step by step, with items you can tick.
    public struct Plan: Sendable, Equatable, Decodable {
        public let title: String?
        public let items: [Item]

        public struct Item: Sendable, Equatable, Decodable, Identifiable {
            public let id: String
            public let text: String
            /// When it happens, in plain words, such as "Fri 6 Nov, morning".
            public let when: String?
            /// How Ari wrote it; a tick on the message overrides it.
            public let done: Bool
        }
    }

    /// A place you might go: it opens in Maps.
    public struct Place: Sendable, Equatable, Decodable {
        public let name: String
        public let address: String?
        public let lat: Double?
        public let lon: Double?
        public let url: URL?
    }

    /// A time worth keeping: it goes into your calendar, on the device.
    public struct Time: Sendable, Equatable, Decodable {
        public let title: String
        /// Local date and time, such as `2026-11-06T08:15`, or a date for all day.
        public let start: String
        public let end: String?
        /// An IANA time zone, such as `Europe/Rome`.
        public let timezone: String
        public let location: String?

        public var isAllDay: Bool { !start.contains("T") }

        /// The start and end as dates, in the time's own zone.
        public var dates: (start: Date, end: Date?)? {
            guard let zone = TimeZone(identifier: timezone), let start = Self.date(start, in: zone)
            else { return nil }
            return (start, end.flatMap { Self.date($0, in: zone) })
        }

        private static func date(_ text: String, in zone: TimeZone) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = text.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
            return formatter.date(from: text)
        }
    }

    /// Options side by side, with the same facts for each, and Ari's pick.
    public struct Compare: Sendable, Equatable, Decodable {
        public private(set) var options: [Option]
        public let pick: String?
        public let why: String?

        /// The facts in the order the block's text names them: decoding forgets an object's order.
        func ordered(as json: String) -> Compare {
            var compare = self
            let place = { (key: String) in
                json.range(of: "\"\(key)\"").map {
                    json.distance(from: json.startIndex, to: $0.lowerBound)
                }
                    ?? .max
            }
            for index in compare.options.indices {
                compare.options[index].facts.sort { place($0.key) < place($1.key) }
            }
            return compare
        }

        public struct Option: Sendable, Equatable, Decodable {
            public let name: String
            /// The facts, in the order Ari wrote them.
            public internal(set) var facts: [(key: String, value: String)]

            public static func == (a: Option, b: Option) -> Bool {
                a.name == b.name && a.facts.map(\.key) == b.facts.map(\.key)
                    && a.facts.map(\.value) == b.facts.map(\.value)
            }

            enum CodingKeys: String, CodingKey { case name, facts }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                let facts = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .facts)
                self.facts = try facts.allKeys.map {
                    ($0.stringValue, try facts.decode(String.self, forKey: $0))
                }
            }
        }
    }

    /// Short answers you might give next. A tap sends the label as a message.
    public struct Choices: Sendable, Equatable, Decodable {
        public let options: [String]
    }

    /// A compact line under a reply, when Ari starts or changes a thing in motion: "Florence with
    /// Janki: booked the Uffizi". Tapping it opens the thing.
    public struct MotionLine: Sendable, Equatable, Decodable {
        public let motion: MotionID
        /// The thing's version the line is about; its note says what changed.
        public let change: Int?
    }

    /// Pictures Ari found on the web, kept on the server as attachments. Never generated.
    public struct Images: Sendable, Equatable, Decodable {
        public let images: [Image]

        public struct Image: Sendable, Equatable, Decodable {
            public let attachment: AttachmentID
            public let alt: String
            public let sourceURL: URL
            public let credit: String

            enum CodingKeys: String, CodingKey {
                case attachment, alt, credit
                case sourceURL = "source_url"
            }
        }
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension ReplyDocument {
    /// The reply's shapes, by the index of the block that holds each, with the part each is: its
    /// index among the reply's `ari:` blocks, counting every kind, read or not.
    public var shapes: [Int: (part: Int, shape: ReplyShape?)] {
        var shapes: [Int: (part: Int, shape: ReplyShape?)] = [:]
        var part = 0
        for (index, block) in blocks.enumerated() {
            guard case .code(let language) = block.kind, language?.hasPrefix("ari:") == true else {
                continue
            }
            let json = block.runs.map(\.text).joined()
            shapes[index] = (part, ReplyShape(language: language, json: json))
            part += 1
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
