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
            // The pinned transcripts' space events are types Ari doesn't know: see OneConversation.
            let type =
                OneConversation.spaceEvents.contains(logged.event.type) ? nil : logged.event.type
            #expect(logged.event.payload.type == type, "\(place): decoded as another type")
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
                    #expect(try !body.decode(ServerInfo.self).lead.name.isEmpty, "\(place)")
                case .send:
                    let sent = try #require(request.body).decode(SendMessage.self)
                    let result = try body.decode(MessageResult.self)
                    #expect(
                        result.message.id == sent.id && result.message.text == sent.text,
                        "\(place)")
                case .earlierMessages:
                    #expect(try !body.decode(MessagePage.self).messages.isEmpty, "\(place)")
                case .desk:
                    _ = try body.decode(Desk.self)
                case .answerCard(let card):
                    #expect(try body.decode(CardResult.self).card.id == card, "\(place)")
                case .done:
                    _ = try body.decode(DonePage.self)
                case .undo(let entry):
                    #expect(try body.decode(DoneResult.self).entry.id == entry, "\(place)")
                case .jobs:
                    _ = try body.decode(JobList.self)
                case .addEvent:
                    _ = try body.decode(CalendarEventResult.self)
                case .lead, .briefingSettings, .readBriefing:
                    // Settings' requests, and a briefing read, which has no answer to read.
                    continue
                case .stop(let turn):
                    #expect(try body.decode(StopResult.self).turn == turn, "\(place)")
                case .retry(let turn):
                    #expect(try body.decode(RetryResult.self).retryOf == turn, "\(place)")
                case .cancelAsk(let ask):
                    #expect(try body.decode(AskResult.self).ask.id == ask, "\(place)")
                case .device:
                    #expect(try body.decode(DeviceResult.self).device.keyID.count == 8, "\(place)")
                case .presence:
                    continue
                case .upload(let attachment, let name):
                    let uploaded = try body.decode(AttachmentResult.self).attachment
                    #expect(uploaded.id == attachment && uploaded.name == name, "\(place)")
                case .pair:
                    #expect(try !body.decode(PairResult.self).token.isEmpty, "\(place)")
                case .capabilities:
                    #expect(try !body.decode(CapabilityList.self).capabilities.isEmpty, "\(place)")
                case .switchCapability(let id), .setUpCapability(let id):
                    #expect(try body.decode(Capability.self).id == id, "\(place)")
                case .checkCapability:
                    _ = try body.decode(CheckResult.self)
                case .memoryInMind:
                    _ = try body.decode(MemoryPages.self)
                case .memoryShelves:
                    _ = try body.decode(ShelfList.self)
                case .memoryPages:
                    _ = try body.decode(PageList.self)
                case .memoryRecent:
                    _ = try body.decode(RecentChanges.self)
                case .memoryPage:
                    #expect(try !body.decode(MemoryPage.self).title.isEmpty, "\(place)")
                case .memoryChange(let change):
                    #expect(try body.decode(PageChange.self).change == change, "\(place)")
                case .models:
                    #expect(try !body.decode(ModelList.self).models.isEmpty, "\(place)")
                case .connectCapability:
                    #expect(try !body.decode(CapabilityConnection.self).code.isEmpty, "\(place)")
                case .chooseModel:
                    let sent = try #require(request.body).decode(ModelChoice.self)
                    #expect(try body.decode(ModelChoice.self) == sent, "\(place)")
                case .startCall(let call), .endCall(let call), .deleteCallAudio(let call):
                    #expect(try body.decode(CallResult.self).call.id == call, "\(place)")
                case .voices:
                    #expect(try !body.decode(VoiceList.self).voices.isEmpty, "\(place)")
                case .forgetVoiceprint:
                    #expect(try body.decode(VoiceList.self).voiceprint == .learning, "\(place)")
                case .chooseVoice:
                    let sent = try #require(request.body).decode(VoiceChoice.self)
                    #expect(try body.decode(VoiceChoice.self) == sent, "\(place)")
                case .motions:
                    #expect(try !body.decode(MotionList.self).motions.isEmpty, "\(place)")
                case .motion(let id):
                    let detail = try body.decode(MotionDetail.self)
                    #expect(detail.motion.id == id, "\(place)")
                    #expect(detail.content != .unreadable && detail.content != .unknown, "\(place)")
                case .motionState:
                    _ = try body.decode(MotionStateBody.self)
                case .speech, .callStream:
                    continue
                case .attachment, .events, .other:
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
                let encoded = SendMessage(
                    id: message.id, text: message.text, attachments: message.attachments ?? [],
                    done: message.done)
                #expect(try JSONValue(encoding: encoded) == body, "\(place)")
            case .answerCard:
                #expect(try JSONValue(encoding: body.decode(CardAnswer.self)) == body, "\(place)")
            case .briefingSettings, .lead:
                // Settings' requests.
                continue
            case .stop:
                Issue.record("\(place): a Stop has no body")
            case .startCall:
                Issue.record("\(place): starting a call has no body")
            case .device:
                let registration = try body.decode(RegisterDevice.self)
                #expect(try JSONValue(encoding: registration) == body, "\(place)")
            case .pair:
                let pairing = try body.decode(PairDevice.self)
                let encoded = PairDevice(code: pairing.code, deviceName: pairing.deviceName)
                #expect(try JSONValue(encoding: encoded) == body, "\(place)")
            case .presence:
                let presence = try body.decode(Presence.self)
                #expect(
                    try JSONValue(encoding: Presence(looking: presence.looking)) == body, "\(place)"
                )
            case .switchCapability:
                let on = try body.decode(SwitchCapability.self).on
                #expect(try JSONValue(encoding: SwitchCapability(on: on)) == body, "\(place)")
            case .chooseModel:
                let choice = try body.decode(ModelChoice.self)
                #expect(
                    try JSONValue(encoding: ModelChoice(model: choice.model, effort: choice.effort))
                        == body, "\(place)")
            case .setUpCapability, .checkCapability:
                let values = try body.decode(CapabilitySetup.self).values
                #expect(
                    try JSONValue(encoding: CapabilitySetup(values: values)) == body, "\(place)")
            case .chooseVoice:
                let voice = try body.decode(VoiceChoice.self).voice
                #expect(try JSONValue(encoding: VoiceChoice(voice: voice)) == body, "\(place)")
            case .speech:
                let speech = try body.decode(SpeechRequest.self)
                #expect(
                    try JSONValue(encoding: SpeechRequest(text: speech.text, voice: speech.voice))
                        == body, "\(place)")
            case .motionState:
                let state = try body.decode(MotionState.self)
                #expect(try JSONValue(encoding: state) == body, "\(place)")
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
        #expect(ProtocolVersion(major: 0, minor: 17) > .supported)
        // By number, not by text: 0.10 comes after 0.9.
        #expect(ProtocolVersion("0.10")! > ProtocolVersion("0.9")!)
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
        case .askStarted: "ask.started"
        case .askEnded: "ask.ended"
        case .messageStarted: "message.started"
        case .messageDelta: "message.delta"
        case .messageEnded: "message.ended"
        case .messagePosted: "message.posted"
        case .turnEnded: "turn.ended"
        case .callStarted: "call.started"
        case .callEnded: "call.ended"
        case .callAudioDeleted: "call.audio_deleted"
        case .voiceStatus: "voice.status"
        case .topicStarted: "topic.started"
        case .messageAmended: "message.amended"
        case .motionStarted: "motion.started"
        case .motionChanged: "motion.changed"
        case .motionFinished: "motion.finished"
        case .motionState: "motion.state"
        case .motionRemoved: "motion.removed"
        case .deskChanged: "desk.changed"
        case .onboardingChanged: "onboarding.changed"
        case .unknown: nil
        }
    }
}
