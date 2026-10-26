import AriKit
import Testing

/// Plays a golden transcript against a ``Conversation``. It starts from the app's cache (the `given`
/// events up to `app.cursor`, without messages older than `app.oldest_cached`). Then it applies every
/// event, every send, Stop and Try again the app made, and every answer that reached it. After each
/// step it checks the rules that must always hold.
struct Replay {
    let transcript: Transcript
    private(set) var conversation = Conversation()
    /// Each message's text worked out from the transcript's lines alone, to compare with the store's.
    private(set) var streamed: [MessageID: [UInt16]] = [:]
    private var position = 0
    private var request: Transcript.Request?
    private var endedTurns: Set<TurnID> = []
    /// The Stop the app sent while its turn ran, followed here apart from the store: until the turn
    /// ends, no more of the cut message may show than was on screen at the tap.
    private var tapped: (turn: TurnID, cut: Cut)?
    /// What the server said of each upload, for your message to show before it's accepted.
    private var uploaded: [AttachmentID: AriKit.Attachment] = [:]

    init(_ transcript: Transcript) {
        self.transcript = transcript
        if let cursor = transcript.header.app.cursor {
            for logged in transcript.given {
                conversation.apply(logged.event)
                record(logged)
                if logged.event.id == cursor { break }
            }
        }
        if let oldest = transcript.header.app.oldestCached {
            conversation.forgetMessages(before: oldest)
        }
    }

    /// Plays the remaining steps, or those up to and including the transcript's line `last`, and
    /// returns the last step it played.
    @discardableResult
    mutating func play(throughLine last: Int = .max) throws -> Transcript.Step? {
        var played: Transcript.Step?
        while position < transcript.steps.count, transcript.steps[position].line <= last {
            let step = transcript.steps[position]
            position += 1
            do {
                try perform(step)
            } catch {
                throw TranscriptError("\(transcript.name).jsonl line \(step.line): \(error)")
            }
            played = step
        }
        return played
    }

    private mutating func perform(_ step: Transcript.Step) throws {
        let before = conversation
        switch step {
        case .event(let logged):
            conversation.apply(logged.event)
            record(logged)
            if case .turnEnded(let ended) = logged.event.payload {
                endedTurns.insert(ended.turn)
                if tapped?.turn == ended.turn { tapped = nil }
            }
        case .app(let request):
            try act(on: request)
            self.request = request
        case .server(let response):
            try answer(response)
            request = nil
        case .world, .push:
            break
        }
        check(after: step, before: before)
    }

    /// Turns a request into what the person did: Send for a new message id (a repeat is the outbox
    /// retrying, which changes nothing), Stop with its cut, or Try again.
    private mutating func act(on request: Transcript.Request) throws {
        switch request.route {
        case .send:
            let message = try #require(request.body).decode(SendMessage.self)
            let secret = message.answers.flatMap { conversation[ask: $0]?.secret } ?? false
            let spoken = message.spoken.map {
                Spoken(
                    call: $0.call, audio: $0.audio.flatMap { uploaded[$0] },
                    corrections: $0.corrections)
            }
            conversation.send(
                message.id, text: message.text, answers: message.answers, secret: secret,
                attachments: (message.attachments ?? []).compactMap { uploaded[$0] },
                spoken: spoken)
        case .stop(let turn):
            let cut = try request.body?.decode(StopTurn.self).cut
            if let cut, conversation.turn?.id == turn { tapped = (turn, cut) }
            conversation.stop(turn: turn, cut: cut)
        case .retry(let turn):
            conversation.retry(turn: turn)
        case .cancelAsk(let ask):
            conversation.cancel(ask)
        default:
            break
        }
    }

    private mutating func answer(_ response: Transcript.Response) throws {
        guard let request, !response.lost, (200..<300).contains(response.status),
            let body = response.body
        else { return }
        switch request.route {
        case .send:
            conversation.confirm(try body.decode(MessageResult.self))
        case .stop:
            let result = try body.decode(StopResult.self)
            // A reply that had already finished shows in full, at once.
            if result.state == .ended, result.outcome == .completed, tapped?.turn == result.turn {
                tapped = nil
            }
            conversation.confirm(result)
        case .retry:
            conversation.confirm(try body.decode(RetryResult.self))
        case .cancelAsk:
            conversation.confirm(try body.decode(AskResult.self))
        case .upload:
            let attachment = try body.decode(AttachmentResult.self).attachment
            uploaded[attachment.id] = attachment
        case .earlierMessages(let before, _):
            conversation.insertEarlier(try body.decode(MessagePage.self), before: before)
        case .startCall, .endCall, .deleteCallAudio:
            conversation.confirm(try body.decode(CallResult.self))
        default:
            break
        }
    }

    /// Follows each message's text from the raw JSON, without Ari's decoding or its store.
    private mutating func record(_ logged: Transcript.LoggedEvent) {
        let json = logged.json
        switch json["type"]?.string {
        case "snapshot":
            for message in json["messages"]?.array ?? [] {
                if let id = message["id"]?.string, let text = message["text"]?.string {
                    streamed[MessageID(id)] = Array(text.utf16)
                }
            }
        case "message.started", "message.accepted":
            if let id = json["message"]?["id"]?.string, let text = json["message"]?["text"]?.string
            {
                streamed[MessageID(id)] = Array(text.utf16)
            }
        case "message.delta":
            if let id = json["message"]?.string, let text = json["text"]?.string {
                streamed[MessageID(id), default: []] += Array(text.utf16)
            }
        case "message.ended":
            if let id = json["message"]?.string, let length = json["length"]?.int {
                streamed[MessageID(id)] = Array((streamed[MessageID(id)] ?? []).prefix(length))
            }
        default:
            break
        }
    }

    private func check(after step: Transcript.Step, before: Conversation) {
        let place = "\(transcript.name).jsonl line \(step.line)"
        let ids = conversation.entries.map(\.id)
        #expect(Set(ids).count == ids.count, "\(place): a message is in the conversation twice")
        #expect(!conversation.needsSnapshot, "\(place): the store found the stream inconsistent")
        if let turn = conversation.turn {
            #expect(
                !endedTurns.contains(turn.id),
                "\(place): turn \(turn.id) is still live after it ended")
        }
        if let tapped, let entry = conversation[tapped.cut.message] {
            #expect(
                conversation.visibleText(of: entry).utf16.count <= tapped.cut.offset,
                "\(place): \(entry.id) shows words after the tap on Stop")
        }

        guard case .event(let logged) = step else {
            expectTextOnlyGrows(from: before, at: place, ending: nil)
            return
        }
        #expect(
            conversation.cursor == logged.event.id, "\(place): the cursor isn't this event's id")
        switch logged.event.payload {
        case .snapshot:
            return
        case .messageEnded(let ended):
            expectTextOnlyGrows(from: before, at: place, ending: ended)
        case .turnStarted(let started):
            for input in started.inputs {
                #expect(
                    conversation[input]?.mark != .next, "\(place): \(input) still waits as Next")
            }
            #expect(conversation.lastEndedTurn == nil, "\(place): the last turn's end lingers")
            expectTextOnlyGrows(from: before, at: place, ending: nil)
        case .turnEnded(let ended):
            #expect(conversation.turn == nil, "\(place): the turn is still live")
            #expect(
                conversation.pendingStop?.turn != ended.turn, "\(place): Stop outlived its turn")
            expectTextOnlyGrows(from: before, at: place, ending: nil)
        default:
            expectTextOnlyGrows(from: before, at: place, ending: nil)
        }
    }

    /// Text is never revised: it only grows, except that a message's end cuts it to its length.
    private func expectTextOnlyGrows(
        from before: Conversation, at place: String, ending: MessageEnded?
    ) {
        for old in before.entries {
            guard let new = conversation[old.id] else { continue }
            let oldUnits = Array(old.text.utf16)
            let newUnits = Array(new.text.utf16)
            #expect(new.length == newUnits.count, "\(place): \(old.id) has the wrong length")
            if let ending, ending.message == old.id {
                #expect(
                    newUnits == Array(oldUnits.prefix(ending.length)),
                    "\(place): \(old.id) didn't end at its length")
            } else {
                #expect(
                    newUnits.starts(with: oldUnits), "\(place): the text of \(old.id) was revised")
            }
        }
    }
}
