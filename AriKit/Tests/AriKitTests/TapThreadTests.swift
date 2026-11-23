import AriKit
import Foundation
import Testing

/// A tap on one of Kumo's cards goes back into the conversation the card is in: in a side thread,
/// your message, and so Kumo's answer, stay in that thread, however late the tap; in the main chat,
/// they stay in the main chat.
@MainActor
@Suite("Taps go back where their card is")
struct TapThreadTests {
    private let thread: ThreadID = "h_0002"
    private let card: MessageID = "m_0001_40000"

    /// A session resumed after the idle conversation of scenario 4, with its stream open.
    private func live() async throws -> Rehearsal {
        let bench = try Rehearsal(try Fixtures.transcript("04-the-agent-stirs"))
        bench.session.start()
        _ = try await bench.nextRequest()
        try await bench.server.answer(200, headers: ["Content-Type": "text/event-stream"])
        await bench.settle()
        return bench
    }

    /// The next message the session sends, once the server has taken the one before.
    private func sent(_ bench: Rehearsal) async throws -> JSONValue? {
        let request = try await bench.nextRequest()
        #expect(request.method == .post && request.path == "/v0/messages")
        return try request.body.map { try JSONValue(data: $0) }
    }

    private func taken(_ bench: Rehearsal, _ id: MessageID, thread: ThreadID?) async throws {
        let place = thread.map { #","thread":"\#($0)""# } ?? ""
        try await bench.server.answer(
            201,
            json:
                #"{"message":{"id":"\#(id)","role":"user","text":"Tapped","at":"2026-10-12T08:41:02.055Z"\#(place)}}"#
        )
        await bench.settle()
    }

    @Test("each kind of tap in a thread goes into that thread, again and again")
    func inAThread() async throws {
        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        let accept = YourTap.decision(.init(message: card, item: "p1", choice: .accept))
        let undo = YourTap.decision(.init(message: card, item: "p1", choice: .undo))
        let attach = YourTap.attach(.init(file: "f_1", version: 2))

        let taps: [MessageID?] = [
            session.send(accept, saying: "Add · Call with Dana", in: thread),
            session.send(undo, saying: "Undo · Call with Dana", in: thread),
            // Approved again, much later: still the card's thread.
            session.send(accept, saying: "Add · Call with Dana", in: thread),
            session.send(attach, saying: "Use version 2 of cv.pdf in the draft", in: thread),
            // A choice under Kumo's reply, and an option of its ask, are your words in the thread.
            session.send("That's the lot", in: thread),
        ]
        let ids = try taps.map { try #require($0) }
        for id in ids {
            #expect(session.conversation(in: thread)[id] != nil)
            #expect(session.conversation[id] == nil)
        }
        for id in ids {
            let body = try #require(try await sent(bench))
            #expect(body["thread"] == .string(thread.rawValue))
            #expect(body["new_thread"] == nil && body["reply_to"] == nil)
            try await taken(bench, id, thread: thread)
        }
        // The block says exactly what was tapped, and your taps read back from the thread.
        let first = try #require(session.conversation(in: thread)[ids[0]])
        #expect(YourTap.taps(in: first.text) == [accept])
        #expect(YourTap.words(of: first.text) == "Add · Call with Dana")
    }

    @Test("a tap on a card in the main chat stays in the main chat")
    func inTheMainChat() async throws {
        let bench = try await live()
        defer { bench.close() }
        let session = bench.session
        let tap = YourTap.decision(.init(message: card, item: "p1", choice: .accept))

        let id = try #require(session.send(tap, saying: "Add · Call with Dana", in: nil))
        #expect(session.conversation[id] != nil)
        #expect(session.threadConversations.isEmpty)
        let body = try #require(try await sent(bench))
        #expect(body["thread"] == nil && body["new_thread"] == nil)
        #expect(body["text"] == .string(tap.message(saying: "Add · Call with Dana")))
    }
}
