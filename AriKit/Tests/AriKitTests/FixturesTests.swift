import AriKit
import Testing

@Suite("The pinned protocol")
struct FixturesTests {
    /// Every parameterized test runs once per transcript, and an empty list would pass silently.
    @Test("holds all thirty-seven transcripts, each named for its scenario")
    func allTranscripts() throws {
        let transcripts = try Fixtures.transcripts()
        #expect(transcripts.map(\.header.scenario) == Array(1...37))
        for transcript in transcripts {
            #expect(transcript.header.transcript == transcript.name)
            #expect(transcript.name.hasPrefix(String(format: "%02d-", transcript.header.scenario)))
        }
    }

    /// A pin that moves to a server speaking another protocol fails here until Ari moves too.
    @Test("speaks the protocol version this build of Ari speaks")
    func protocolVersion() throws {
        let transcript = try Fixtures.transcript("01-first-connection")
        var request: Transcript.Request?
        var checked = 0
        for step in transcript.steps {
            switch step {
            case .app(let sent):
                request = sent
            case .server(let response):
                if let header = response.headers["Ito-Protocol"] {
                    #expect(ProtocolVersion(header) == .supported)
                }
                if request?.route == .discover, let body = response.body {
                    #expect(try body.decode(Discovery.self).versions.contains(.supported))
                    checked += 1
                }
                if request?.route == .server, response.status == 200, let body = response.body {
                    #expect(try body.decode(ServerInfo.self).protocolVersion == .supported)
                    checked += 1
                }
            default:
                break
            }
        }
        #expect(checked == 2)
    }
}
