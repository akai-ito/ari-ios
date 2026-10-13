import Foundation

/// Reads Server-Sent Events from a body that arrives in arbitrary pieces, following the HTML
/// standard's rules: lines end in LF, CRLF or CR; a blank line ends an event; a line starting with a
/// colon is a comment, which Ito sends as `: ping` to keep the stream alive.
///
/// `URLSession.AsyncBytes.lines` can't be used for this: it skips blank lines, and a blank line is
/// what ends an event.
struct EventStreamParser {
    enum Item: Equatable {
        case event(ServerSentEvent)
        case comment(String)
    }

    private var line: [UInt8] = []
    private var afterCR = false
    private var atStart = true
    private var type = ""
    private var data: [String] = []
    private var id: String?

    mutating func feed(_ chunk: Data) -> [Item] {
        var items: [Item] = []
        for byte in chunk {
            if afterCR {
                afterCR = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0A:
                endLine(into: &items)
            case 0x0D:
                afterCR = true
                endLine(into: &items)
            default:
                line.append(byte)
            }
        }
        return items
    }

    private mutating func endLine(into items: inout [Item]) {
        var bytes = line[...]
        line.removeAll(keepingCapacity: true)
        if atStart {
            atStart = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        }
        let text = String(decoding: bytes, as: UTF8.self)
        if text.isEmpty {
            if !data.isEmpty {
                items.append(
                    .event(ServerSentEvent(id: id, type: type, data: data.joined(separator: "\n"))))
            }
            type = ""
            data = []
            id = nil
            return
        }
        if text.hasPrefix(":") {
            var comment = text.dropFirst()
            if comment.hasPrefix(" ") { comment = comment.dropFirst() }
            items.append(.comment(String(comment)))
            return
        }
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = text[...]
            value = ""
        }
        switch field {
        case "event": type = String(value)
        case "data": data.append(String(value))
        case "id" where !value.contains("\u{0}"): id = String(value)
        default: break
        }
    }
}

/// One event from an event stream.
struct ServerSentEvent: Equatable, Sendable {
    var id: String?
    var type: String
    var data: String
}
