import Foundation

/// What Ari says aloud on a call. While a call is on, the agent writes the spoken gist, then a line
/// holding only `---`, then the detail for the chat: Ari speaks only what comes before the line.
public enum SpokenText {
    /// The part of a reply or note to speak: everything before a line holding only `---`, as plain
    /// words without Markdown.
    public static func spoken(from text: String) -> String {
        speakable(String(text[..<(divider(in: text)?.lowerBound ?? text.endIndex)]))
    }

    /// Whether the text has reached the divider, so nothing after it is spoken.
    public static func hasDivider(_ text: String) -> Bool {
        divider(in: text) != nil
    }

    /// The divider line, `---` on a line of its own, if the text has one yet. One still being
    /// written (no line end after it yet) counts once the text ends there.
    private static func divider(in text: String) -> Range<String.Index>? {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces) == "---" {
                return lineStart..<lineEnd
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        return nil
    }

    /// Markdown as it should sound: no stars, backticks, heading marks or link targets, and list
    /// items as sentences.
    public static func speakable(_ markdown: String) -> String {
        var lines: [String] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = line.trimmingCharacters(in: .whitespaces)
            while line.hasPrefix("#") { line.removeFirst() }
            for marker in ["- ", "* ", "+ ", "> "] where line.hasPrefix(marker) {
                line.removeFirst(marker.count)
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber),
                !line[..<dot].isEmpty, line[line.index(after: dot)...].hasPrefix(" ")
            {
                line = String(line[line.index(dot, offsetBy: 2)...])
            }
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        var text = lines.filter { !$0.isEmpty }.map { line in
            line.last.map { ".!?:;,".contains($0) } == true ? line : line + "."
        }.joined(separator: " ")
        // [words](target) says the words.
        text = text.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.1) }
        text.removeAll { "*`_".contains($0) }
        return text
    }
}

/// Feeds a reply to the voice a sentence at a time while it streams, so Ari starts speaking before
/// the reply is finished.
public struct SentenceFeed: Sendable {
    /// How much of the text has gone to the voice, in characters of the spoken part.
    private var spokenCount = 0

    public init() {}

    /// The whole sentences of `text` not spoken yet. With `finished`, the rest goes too.
    public mutating func next(from text: String, finished: Bool) -> [String] {
        let spoken = SpokenText.spoken(from: text)
        let done = finished || SpokenText.hasDivider(text)
        let characters = Array(spoken)
        guard spokenCount < characters.count else { return [] }
        let rest = characters[spokenCount...]
        var end = rest.startIndex
        var sentences: [String] = []
        var start = rest.startIndex
        var index = rest.startIndex
        while index < rest.endIndex {
            let character = rest[index]
            let next = index + 1
            // A sentence ends at . ! or ? followed by a space, once the next word has begun, so
            // "3.5" and "e.g." mid-stream aren't cut.
            if ".!?".contains(character), next < rest.endIndex, rest[next] == " ",
                next + 1 < rest.endIndex
            {
                let sentence = String(rest[start...index]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { sentences.append(sentence) }
                start = next
                end = next
            }
            index = next
        }
        if done {
            let tail = String(rest[start...]).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { sentences.append(tail) }
            end = rest.endIndex
        }
        spokenCount = end
        return sentences
    }
}
