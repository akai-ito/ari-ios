import AriKit
import Foundation
import Testing

@Suite("Decoding the protocol")
struct ProtocolDecodingTests {
    @Test(
        "every event decodes as its own type, keeping its id", arguments: try Fixtures.transcripts()
    )
    func events(_ transcript: Transcript) throws {
        for logged in transcript.events {
            let place = "\(transcript.name).jsonl line \(logged.line)"
            #expect(logged.event.type == logged.json["type"]?.string, "\(place)")
            #expect(logged.event.id?.rawValue == logged.json["id"]?.string, "\(place)")
            #expect(
                logged.event.payload.type == logged.event.type, "\(place): decoded as another type")
        }
    }

    @Test(
        "every answer decodes as the answer to its request", arguments: try Fixtures.transcripts())
    func answers(_ transcript: Transcript) throws {
        var request: Transcript.Request?
        for step in transcript.steps {
            switch step {
            case .app(let sent):
                request = sent
            case .server(let response):
                guard let request, let body = response.body else { continue }
                let place = "\(transcript.name).jsonl line \(response.line)"
                guard (200..<300).contains(response.status) else {
                    let error = try body.decode(ErrorResult.self).error
                    #expect(!error.message.isEmpty, "\(place)")
                    continue
                }
                switch request.route {
                case .discover:
                    #expect(try body.decode(Discovery.self).product == "ito", "\(place)")
                case .server:
                    #expect(try !body.decode(ServerInfo.self).agent.name.isEmpty, "\(place)")
                case .send:
                    let sent = try #require(request.body).decode(SendMessage.self)
                    let result = try body.decode(MessageResult.self)
                    #expect(
                        result.message.id == sent.id && result.message.text == sent.text, "\(place)"
                    )
                case .earlierMessages:
                    #expect(try !body.decode(MessagePage.self).messages.isEmpty, "\(place)")
                case .stop(let turn):
                    #expect(try body.decode(StopResult.self).turn == turn, "\(place)")
                case .retry(let turn):
                    #expect(try body.decode(RetryResult.self).retryOf == turn, "\(place)")
                case .events, .other:
                    Issue.record("\(place): an unexpected body")
                }
            default:
                continue
            }
        }
    }

    /// Requests are compared as JSON, so a misnamed key or an upper-case UUID shows up.
    @Test(
        "requests encode exactly as the transcripts send them",
        arguments: try Fixtures.transcripts())
    func requests(_ transcript: Transcript) throws {
        for case .app(let request) in transcript.steps {
            guard let body = request.body else { continue }
            let place = "\(transcript.name).jsonl line \(request.line)"
            switch request.route {
            case .send:
                let message = try body.decode(SendMessage.self)
                #expect(
                    try JSONValue(encoding: SendMessage(id: message.id, text: message.text))
                        == body, "\(place)")
            case .stop:
                let stop = try body.decode(StopTurn.self)
                #expect(try JSONValue(encoding: StopTurn(cut: stop.cut)) == body, "\(place)")
            default:
                Issue.record("\(place): an unexpected request body")
            }
        }
    }

    @Test("a known event with a malformed field fails to decode")
    func malformed() throws {
        let delta =
            #"{"id":"e_1","type":"message.delta","at":"2026-10-12T08:41:03.861Z","message":"m_1","offset":"0","text":"Hi"}"#
        #expect(throws: DecodingError.self) { try JSONValue(json: delta).decode(Event.self) }
    }

    @Test("protocol versions are MAJOR.MINOR and nothing else")
    func protocolVersions() {
        #expect(ProtocolVersion("0.1") == ProtocolVersion(major: 0, minor: 1))
        #expect(ProtocolVersion("12.30")?.description == "12.30")
        for text in ["0.1.7", "1", "0.", ".1", "a.b", "0.-1", "\u{0660}.\u{0661}", ""] {
            #expect(ProtocolVersion(text) == nil, "\(text)")
        }
        #expect(ProtocolVersion(major: 0, minor: 3) > .supported)
    }

    @Test("timestamps keep the server's text, milliseconds included")
    func timestamps() throws {
        let timestamp = try #require(Timestamp("2026-10-12T08:41:09.180Z"))
        #expect(try JSONValue(encoding: timestamp) == .string("2026-10-12T08:41:09.180Z"))
        #expect(timestamp.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) > 0.17)
        #expect(Timestamp("yesterday") == nil)
    }
}

extension Event.Payload {
    /// The wire type this payload decodes, or `nil` for one Ari doesn't know.
    var type: String? {
        switch self {
        case .snapshot: "snapshot"
        case .messageAccepted: "message.accepted"
        case .messageQueued: "message.queued"
        case .messageRead: "message.read"
        case .turnStarted: "turn.started"
        case .turnStatus: "turn.status"
        case .stepStarted: "step.started"
        case .stepUpdated: "step.updated"
        case .stepEnded: "step.ended"
        case .messageStarted: "message.started"
        case .messageDelta: "message.delta"
        case .messageEnded: "message.ended"
        case .turnEnded: "turn.ended"
        case .unknown: nil
        }
    }
}
