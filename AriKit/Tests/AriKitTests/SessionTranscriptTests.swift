import AriKit
import Foundation
import Testing

/// Level 2: the whole client against each golden transcript. The transcript's server answers
/// through the transport seam, and Ari must make exactly the transcript's requests, in order, and
/// end with the same conversation as the store does when fed the transcript directly.
@MainActor
@Suite("The client, scenario by scenario")
struct SessionTranscriptTests {
    @Test(
        "makes exactly the transcript's requests and ends with the store's conversation",
        arguments: try Fixtures.transcripts().filter {
            $0.name != "01-first-connection" && !$0.registersDevices
        })
    func plays(_ transcript: Transcript) async throws {
        let rehearsal = try Rehearsal(transcript, sending: Self.sentEarly[transcript.name] ?? [])
        defer { rehearsal.close() }
        try await rehearsal.play()
        var replay = Replay(transcript)
        try replay.play()
        #expect(rehearsal.session.conversation == replay.conversation)
        #expect(
            await rehearsal.server.takeRequest() == nil, "Ari made a request the transcript doesn't"
        )
    }

    /// Scenarios 18, 21, 24 and 26 register the device and say when you're looking, which arrives
    /// with notifications; until then the store plays them, and the session doesn't.

    /// Messages you send before their requests go: in scenario 12, both while offline.
    static let sentEarly: [String: [(id: String, at: Int)]] = [
        "12-send-while-offline": [
            ("76c3ac95-83e0-45e9-a821-a12c08d956e9", 3_000),
            ("0c1566bf-a262-4595-b7a6-dd608ba8c3b0", 6_000),
        ]
    ]
}

extension Transcript {
    /// Whether the scenario registers a device or says when you're looking.
    fileprivate var registersDevices: Bool {
        steps.contains { step in
            guard case .app(let request) = step else { return false }
            return request.route == .device || request.route == .presence
        }
    }
}
