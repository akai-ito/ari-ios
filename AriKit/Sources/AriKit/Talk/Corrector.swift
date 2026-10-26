import Foundation

/// Corrects what the recogniser heard against the vocabulary, after each turn on a call, and says
/// what it changed. It's conservative: a wrong name is worse than a misheard one, since a misheard
/// one at least looks wrong.
///
/// - A **learnt mishearing** (a term's `heard`) is always corrected, whole words only.
/// - A **near miss** is corrected only for a name of six letters or more, from a word the
///   dictionary doesn't know, that starts the same and is one letter off (two for a name of nine
///   or more), when exactly one name is that close.
public struct Corrector: Sendable {
    /// Learnt mishearings, folded, with what they mean: the longest first.
    private let learnt: [(heard: [String], meant: String)]
    /// Names a near miss can become, folded, with how they're written.
    private let names: [(folded: String, text: String)]
    /// Every term's words, folded: a word already in the vocabulary is never corrected.
    private let known: Set<String>
    private let isWord: @Sendable (String) -> Bool
    private let refused: Set<Refusal>

    /// A correction you undid, so it isn't made again.
    public struct Refusal: Hashable, Sendable, Codable {
        public let heard: String
        public let meant: String

        public init(heard: String, meant: String) {
            self.heard = Corrector.fold(heard)
            self.meant = meant
        }
    }

    /// - Parameters:
    ///   - isWord: Whether a word is in the dictionary, such as `UITextChecker` says; a word it
    ///     knows is never corrected as a near miss.
    ///   - refused: Corrections you undid.
    public init(
        vocabulary: Vocabulary, isWord: @escaping @Sendable (String) -> Bool = { _ in false },
        refused: Set<Refusal> = []
    ) {
        var learnt: [(heard: [String], meant: String)] = []
        var names: [(folded: String, text: String)] = []
        var known: Set<String> = []
        for term in vocabulary.terms {
            let words = Self.words(in: term.text).map { Self.fold($0.text) }
            known.formUnion(words)
            for heard in term.heard {
                let heardWords = Self.words(in: heard).map { Self.fold($0.text) }
                if !heardWords.isEmpty, heardWords != words {
                    learnt.append((heardWords, term.text))
                }
            }
            if term.kind != .term, words.count == 1, let folded = words.first,
                folded.count >= 6, !isWord(folded)
            {
                names.append((folded, term.text))
            }
        }
        self.learnt = learnt.sorted { $0.heard.count > $1.heard.count }
        self.names = names
        self.known = known
        self.isWord = isWord
        self.refused = refused
    }

    /// The corrected text, and each correction with its place in it.
    public func correct(_ text: String) -> (text: String, corrections: [Correction]) {
        let words = Self.words(in: text)
        let folded = words.map { Self.fold($0.text) }
        var output = ""
        var corrections: [Correction] = []
        var cursor = text.startIndex
        var index = 0
        while index < words.count {
            guard let (count, meant) = replacement(at: index, words: words, folded: folded) else {
                index += 1
                continue
            }
            let range = words[index].range.lowerBound..<words[index + count - 1].range.upperBound
            let heard = String(text[range])
            output += text[cursor..<range.lowerBound]
            corrections.append(
                Correction(
                    offset: output.utf16.count, length: meant.utf16.count, heard: heard))
            output += meant
            cursor = range.upperBound
            index += count
        }
        output += text[cursor...]
        return (output, corrections)
    }

    private func replacement(at index: Int, words: [Word], folded: [String]) -> (Int, String)? {
        for (heard, meant) in learnt where index + heard.count <= folded.count {
            guard Array(folded[index..<index + heard.count]) == heard else { continue }
            let said = words[index..<index + heard.count].map(\.text).joined(separator: " ")
            guard said != meant, !refused.contains(Refusal(heard: said, meant: meant)) else {
                continue
            }
            return (heard.count, meant)
        }
        let word = folded[index]
        guard word.count >= 4, !known.contains(word), !isWord(word) else { return nil }
        let close = names.filter { name in
            name.folded.first == word.first
                && Self.distance(word, name.folded) <= (name.folded.count >= 9 ? 2 : 1)
        }
        guard close.count == 1, let name = close.first,
            !refused.contains(Refusal(heard: words[index].text, meant: name.text))
        else { return nil }
        return (1, name.text)
    }

    // MARK: - Words

    private struct Word {
        let text: String
        let range: Range<String.Index>
    }

    /// Runs of letters and digits, with apostrophes inside a word.
    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            let inside =
                character.isLetter || character.isNumber
                || (character == "'" || character == "’") && start != nil && next < text.endIndex
                    && text[next].isLetter
            if inside {
                if start == nil { start = index }
            } else if let begun = start {
                words.append(Word(text: String(text[begun..<index]), range: begun..<index))
                start = nil
            }
            index = next
        }
        if let begun = start {
            words.append(Word(text: String(text[begun...]), range: begun..<text.endIndex))
        }
        return words
    }

    /// Lower case, without accents, so "Ljubljana" and "ljubljana" match.
    static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Edits between two words, a swap of neighbours counting as one.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var rows = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { rows[i][0] = i }
        for j in 0...b.count { rows[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[a.count][b.count]
    }
}
