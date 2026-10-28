import AriKit
import Foundation
import Testing

/// Topics: the label Ari puts on the message that changed the subject.
@MainActor
@Suite("Topics")
struct TopicTests {
    @Test("Scenario 58: the snapshot carries its topics, and a label sits just above its message")
    func labels() throws {
        var replay = Replay(try Fixtures.transcript("58-topics"))
        try replay.play()
        let topics = replay.conversation.topics
        #expect(topics.map(\.label) == ["Florence trip", "QRT panel", "Florence trip"])
        let items = Timeline(replay.conversation, reveal: Reveal()).items.map(\.id)
        let florence = try #require(items.firstIndex(of: "topic p_0001_87693"))
        #expect(items[florence + 1] == "f65434eb-176c-4547-a4b5-f1abc606ee0b")
        let qrt = try #require(items.firstIndex(of: "topic p_0002_76103"))
        #expect(items[qrt + 1] == "be0f8920-f03b-49fd-a28a-bcbd21c203c5")
        // A follow-up gets no label of its own.
        let followUp = try #require(items.firstIndex(of: "cb9b4fdb-78c4-4977-9a19-a86f2ec1a221"))
        #expect(!items[followUp - 1].hasPrefix("topic"))
    }

    @Test("forgetting older messages keeps a topic on the first message kept")
    func window() throws {
        var replay = Replay(try Fixtures.transcript("58-topics"))
        try replay.play()
        var conversation = replay.conversation
        conversation.forgetMessages(before: "be0f8920-f03b-49fd-a28a-bcbd21c203c5")
        #expect(conversation.topics.map(\.label) == ["QRT panel", "Florence trip"])
    }
}
