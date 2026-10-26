import AriKit
import Foundation
import Testing

@Suite("Speech on a call")
struct SpokenTests {
    static let vocabulary = Vocabulary(terms: [
        .init(text: "Bora", kind: .person, weight: 1, heard: ["Bara"]),
        .init(text: "QRT panel", kind: .project, weight: 1, heard: ["cutie panel"]),
        .init(text: "QRT", kind: .term, weight: 0.5, heard: ["cutie"]),
        .init(text: "Ljubljana", kind: .place, weight: 1),
        .init(text: "Optiver", kind: .project, weight: 1),
        .init(text: "Dahab", kind: .place, weight: 1),
        .init(text: "Citadel", kind: .project, weight: 1),
    ])

    @Test("a learnt mishearing is corrected, longest first, and the correction says where")
    func learnt() {
        let corrector = Corrector(vocabulary: Self.vocabulary)
        let (text, corrections) = corrector.correct("What did Bara say about the cutie panel?")
        #expect(text == "What did Bora say about the QRT panel?")
        #expect(corrections == [
            Correction(offset: 9, length: 4, heard: "Bara"),
            Correction(offset: 28, length: 9, heard: "cutie panel"),
        ])
        let (alone, _) = corrector.correct("Cutie, I said.")
        #expect(alone == "QRT, I said.")
    }

    @Test("a near miss becomes a long name only when the dictionary doesn't know the word")
    func nearMiss() {
        let dictionary: Set<String> = ["citadel", "the", "hub", "octave", "said"]
        let corrector = Corrector(vocabulary: Self.vocabulary, isWord: { dictionary.contains($0) })
        #expect(corrector.correct("Back from Lubljana today").text == "Back from Ljubljana today")
        #expect(corrector.correct("The Optivar call went fine").text == "The Optiver call went fine")
        // Too far off, a real word, or a name too short to guess.
        #expect(corrector.correct("Octava said yes").corrections.isEmpty)
        #expect(corrector.correct("diving in the hub").corrections.isEmpty)
        #expect(corrector.correct("Dahob was hot").corrections.isEmpty)
        // A name already right is left alone.
        #expect(corrector.correct("Citadel went well").corrections.isEmpty)
    }

    @Test("a correction you undid isn't made again")
    func refused() {
        let corrector = Corrector(
            vocabulary: Self.vocabulary, refused: [.init(heard: "Bara", meant: "Bora")])
        #expect(corrector.correct("Bara is a friend").corrections.isEmpty)
    }

    @Test("offsets count UTF-16, past emoji and accents")
    func offsets() {
        let corrector = Corrector(vocabulary: Self.vocabulary)
        let (text, corrections) = corrector.correct("🏃 Café with Bara")
        let correction = try! #require(corrections.first)
        let start = text.utf16.index(text.utf16.startIndex, offsetBy: correction.offset)
        let end = text.utf16.index(start, offsetBy: correction.length)
        #expect(String(text[start..<end]) == "Bora")
    }

    @Test("Ari speaks what comes before a line holding only ---, without Markdown")
    func divider() {
        let reply = """
            She wants **one more round** on your design. I've put the list in the chat.
            ---
            1. Tighten the intro
            2. Add the latency numbers
            """
        #expect(
            SpokenText.spoken(from: reply)
                == "She wants one more round on your design. I've put the list in the chat.")
        #expect(SpokenText.spoken(from: "- Eggs\n- [Milk](https://shop.example)") == "Eggs. Milk.")
        #expect(SpokenText.spoken(from: "A rule --- inside a line stays") == "A rule --- inside a line stays.")
    }

    @Test("a streaming reply goes to the voice a sentence at a time, and stops at the divider")
    func feed() {
        var feed = SentenceFeed()
        #expect(feed.next(from: "She wants one more", finished: false).isEmpty)
        #expect(feed.next(from: "She wants one more round. The panel", finished: false) == [
            "She wants one more round."
        ])
        #expect(feed.next(from: "She wants one more round. The panel sits in Nov", finished: false).isEmpty)
        #expect(
            feed.next(from: "She wants one more round. The panel sits in 3.5 weeks.\n---\nDetail.", finished: false)
                == ["The panel sits in 3.5 weeks."])
        #expect(
            feed.next(from: "She wants one more round. The panel sits in 3.5 weeks.\n---\nDetail. More.", finished: true)
                .isEmpty)
    }
}
