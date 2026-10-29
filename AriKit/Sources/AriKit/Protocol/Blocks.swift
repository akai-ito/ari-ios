import Foundation

/// Where part of a reply does something Markdown can't, Ari writes it as a fenced block, `ari:` and a
/// kind, holding one JSON object, and the app draws it: a place on a map, short answers to tap,
/// pictures Ari found, a line that opens a thing in motion. A block Ari doesn't know, or whose JSON
/// doesn't read, shows as its fenced text. Everything else in a reply is Markdown.
public enum ReplyShape: Sendable, Equatable {
    case place(Place)
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
            case "place": self = .place(try decoder.decode(Place.self, from: data))
            case "choices": self = .choices(try decoder.decode(Choices.self, from: data))
            case "images": self = .images(try decoder.decode(Images.self, from: data))
            case "motion": self = .motion(try decoder.decode(MotionLine.self, from: data))
            default: return nil
            }
        } catch {
            return nil
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
        public let images: [Photo]
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
