import AriKit
import Foundation
import Testing

/// Side threads: conversations of their own beside the main chat, each fed by the same stream.
@MainActor
@Suite("Threads")
struct ThreadTests {
    @Test(
        "Scenario 58: Kumo moves your photo into a thread; the main chat keeps its line and goes on"
    )
    func branched() throws {
        var replay = Replay(try Fixtures.transcript("58-side-threads"))
        try replay.play()
        let question: MessageID = "6e78d2ef-49bf-4908-94b9-6105ca77ce83"
        let aside: MessageID = "3985aa7c-9e7c-4569-8e9d-03ce76358807"
        let thread: ThreadID = "h_0001_12800"

        // The photo left the main chat, and the thread's line sits where it was, before the aside.
        #expect(replay.conversation[question] == nil)
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        let line = try #require(items.firstIndex(of: "thread \(thread)"))
        let next = try #require(items.firstIndex(of: aside.rawValue))
        #expect(line < next)

        // The thread has the photo and Kumo's answer, done, with its result and nothing unseen.
        let opened = try #require(replay.threads[thread])
        #expect(opened[question]?.attachments.first?.kind == .image)
        #expect(opened.entries.filter(\.isShown).count == 2)
        let summary = try #require(replay.conversation.threads[thread])
        #expect(summary.state == .done && summary.done?.by == .kumo)
        #expect(summary.result == "Thames Path by Hampton Court: worth it")
        #expect(summary.news == nil && summary.picture != nil)
        #expect(opened.thread == summary)
    }

    @Test(
        "Scenario 90: a reply thread hangs under its message, quotes, moves a message and reopens")
    func replyThread() throws {
        var replay = Replay(try Fixtures.transcript("90-reply-in-a-thread"))
        try replay.play()
        let anchor: MessageID = "m_0002_71695"
        let thread: ThreadID = "h_0001_33878"
        let legs: MessageID = "c18c0493-767c-4d3c-acf5-9069508bac2a"
        let moved: MessageID = "8fe045b5-9d87-49c0-82e4-46462772ba40"

        // Under the message it hangs from, straight after it.
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        let below = try #require(items.firstIndex(of: anchor.rawValue))
        #expect(items[below + 1] == "thread \(thread)")
        #expect(replay.conversation.thread(hangingFrom: anchor)?.id == thread)

        let opened = try #require(replay.threads[thread])
        #expect(opened.anchor?.id == anchor)
        #expect(opened[legs]?.quotes?.text.hasPrefix("Slower than 6:30 a km") == true)
        // The message you moved left the thread for the main chat, keeping its id.
        #expect(opened[moved] == nil && replay.conversation[moved] != nil)
        let summary = try #require(replay.conversation.threads[thread])
        #expect(summary.title == "Saturday run" && summary.isOpen && summary.done == nil)
        #expect(summary.by == .you)
    }

    @Test(
        "Scenario 91: Kumo comes back to a thread: its line moves to the end with the news, then done"
    )
    func comesBack() throws {
        var replay = Replay(try Fixtures.transcript("91-kumo-comes-back-to-a-thread"))
        try replay.play(throughLine: 38)
        let thread: ThreadID = "h_0001_83442"
        let news = try #require(replay.conversation.threads[thread]?.news)
        #expect(news.text == "Theo confirmed you for 11:30 on Saturday. It's in your calendar.")
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        #expect(items.last == "thread \(thread)")

        try replay.play()
        let summary = try #require(replay.conversation.threads[thread])
        #expect(summary.title == "Haircut" && summary.state == .done)
        #expect(replay.conversation.openThreads.isEmpty)
    }

    @Test("a thread keeps only its own messages and turns, and the main chat only its own")
    func places() throws {
        let at = "2026-11-21T12:41:00.000Z"
        let thread = #","thread":"h_1""#
        let lines = [
            #"{"id":"e_1","type":"turn.started","at":"\#(at)","turn":"t_side","inputs":["u_1"]\#(thread)}"#,
            #"{"id":"e_2","type":"message.started","at":"\#(at)","message":{"id":"m_side","role":"agent","kind":"reply","turn":"t_side","text":"","at":"\#(at)","position":2\#(thread)}}"#,
            #"{"id":"e_3","type":"message.delta","at":"\#(at)","message":"m_side","offset":0,"text":"Noodles"\#(thread)}"#,
            #"{"id":"e_4","type":"turn.started","at":"\#(at)","turn":"t_main","inputs":["u_2"]}"#,
            #"{"id":"e_5","type":"message.started","at":"\#(at)","message":{"id":"m_main","role":"agent","kind":"reply","turn":"t_main","text":"","at":"\#(at)","position":5}}"#,
            #"{"id":"e_6","type":"message.delta","at":"\#(at)","message":"m_main","offset":0,"text":"Dry until six"}"#,
            #"{"id":"e_7","type":"step.started","at":"\#(at)","step":{"id":"s_1","turn":"t_side","kind":"search","title":"Searching","at":"\#(at)","position":7}}"#,
        ]
        var main = Conversation()
        var side = Conversation(place: "h_1")
        for line in lines {
            let event = try JSONDecoder().decode(Event.self, from: Data(line.utf8))
            main.apply(event)
            side.apply(event)
        }
        #expect(main.entries.map(\.id) == ["m_main"] && main.turn?.id == "t_main")
        #expect(side.entries.map(\.id) == ["m_side"] && side.turn?.id == "t_side")
        #expect(main.steps.isEmpty && side.steps.map(\.id) == ["s_1"])
        #expect(!main.needsSnapshot && !side.needsSnapshot)
    }
}
