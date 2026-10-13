import Foundation
import Testing

@testable import AriKit

@Suite("Reading the event stream")
struct EventStreamParserTests {
    private let body = Data(
        """
        \u{FEFF}: ping

        id: e_1
        event: message.delta
        data: {"a":1}

        : ping
        data: first line
        data:second line
        retry: 3000

        id: e_3\r\nevent: turn.ended\r\ndata: {}\r\n\r\nid: e_4\revent: x\rdata: y\r\r
        """.utf8)

    private let expected: [EventStreamParser.Item] = [
        .comment("ping"),
        .event(ServerSentEvent(id: "e_1", type: "message.delta", data: #"{"a":1}"#)),
        .comment("ping"),
        .event(ServerSentEvent(id: nil, type: "", data: "first line\nsecond line")),
        .event(ServerSentEvent(id: "e_3", type: "turn.ended", data: "{}")),
        .event(ServerSentEvent(id: "e_4", type: "x", data: "y")),
    ]

    @Test("events, comments and every kind of line ending, from one piece")
    func whole() {
        var parser = EventStreamParser()
        #expect(parser.feed(body) == expected)
    }

    @Test("the same, however the body is split, even inside a character or a CRLF")
    func split() {
        for size in [1, 2, 3, 7, 64] {
            var parser = EventStreamParser()
            var items: [EventStreamParser.Item] = []
            var start = body.startIndex
            while start < body.endIndex {
                let end =
                    body.index(start, offsetBy: size, limitedBy: body.endIndex) ?? body.endIndex
                items += parser.feed(body[start..<end])
                start = end
            }
            #expect(items == expected, "in pieces of \(size)")
        }
        var parser = EventStreamParser()
        let emoji = Data("data: 🚲\n\n".utf8)
        #expect(parser.feed(emoji.prefix(8)) == [])
        #expect(
            parser.feed(emoji.dropFirst(8)) == [
                .event(ServerSentEvent(id: nil, type: "", data: "🚲"))
            ])
    }
}

@Suite("The outbox")
struct OutboxTests {
    @Test("keeps your messages in order across a restart, each once")
    func order() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AriKitTests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = OutboxStore(directory: directory)
        let messages = (1...4).map { SendMessage(id: MessageID("m\($0)"), text: "Message \($0)") }
        for message in messages { try outbox.add(message) }
        try outbox.add(messages[0])
        try outbox.remove("m2")
        try outbox.add(SendMessage(id: "m5", text: "Message 5"))

        let reopened = OutboxStore(directory: directory)
        #expect(try reopened.load().map(\.id) == ["m1", "m3", "m4", "m5"])
        #expect(try reopened.load().first?.text == "Message 1")
    }
}

@Suite("Waiting before trying again")
struct BackoffTests {
    @Test("messages wait 2 s then double to 30; the stream half a second to 30; the server can say")
    func delays() {
        #expect(Session.sendDelay(after: 1, .network(.timedOut)) == .seconds(2))
        #expect(Session.sendDelay(after: 3, .network(.timedOut)) == .seconds(8))
        #expect(Session.sendDelay(after: 9, .network(.timedOut)) == .seconds(30))
        #expect(Session.reconnectDelay(after: 1) == .milliseconds(500))
        #expect(Session.reconnectDelay(after: 20) == .seconds(30))
        let busy = RequestError.refused(status: 429, error: nil, retryAfter: .seconds(7))
        #expect(Session.sendDelay(after: 1, busy) == .seconds(7))
    }
}
