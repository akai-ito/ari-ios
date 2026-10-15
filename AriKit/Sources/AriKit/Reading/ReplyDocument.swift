import Foundation
import Markdown

/// A reply's Markdown, read into blocks Ari draws itself. Parsing is Apple's swift-markdown, so it
/// follows GitHub's rules exactly; drawing stays Ari's, which the reading pace needs. Every run of
/// text knows where it starts in the source, in UTF-16 units (the unit of Stop's cut), so the
/// screen can hide what hasn't been revealed yet without moving anything.
public struct ReplyDocument: Sendable, Equatable {
    public var blocks: [Block]

    /// A paragraph, heading, code block or rule. A list item's paragraphs are blocks too, deeper
    /// in, with the item's marker on the first.
    public struct Block: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case paragraph
            case heading(Int)
            case code(language: String?)
            case rule
        }

        public var kind: Kind
        /// How many lists deep it sits; 0 outside any.
        public var depth: Int
        /// The list item's marker, "•" or "1.", on its first block only.
        public var marker: String?
        /// Inside a block quote.
        public var quoted: Bool
        public var runs: [Run]
        /// Where it starts in the source: it shows once the reveal gets here.
        public var start: Int
    }

    /// Text in one style. Its characters map one to one onto the source from `start`, except for
    /// the rare escape (`\*`).
    public struct Run: Sendable, Equatable {
        public var text: String
        public var style: Style
        public var link: URL?
        public var start: Int
    }

    public struct Style: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let strong = Style(rawValue: 1 << 0)
        public static let emphasis = Style(rawValue: 1 << 1)
        public static let code = Style(rawValue: 1 << 2)
        public static let strikethrough = Style(rawValue: 1 << 3)
    }

    /// Reads `markdown`, which may be a reply still arriving: a bold or code span left open at
    /// the end is read as closed, so its markers never flash on screen.
    public init(markdown: String) {
        var reader = Reader(map: SourceMap(markdown))
        // No smart punctuation: "--" becoming "–" would shift every offset after it, and the
        // text should be exactly what the server sent.
        let document = Document(
            parsing: Self.closingOpenSpans(markdown), options: .disableSmartOpts)
        reader.read(document, depth: 0, quoted: false)
        blocks = reader.blocks
    }

    /// The text with an unclosed `**` or backtick in its last paragraph closed. Inside an open
    /// code fence nothing is added: the parser already runs the block to the end.
    static func closingOpenSpans(_ text: String) -> String {
        guard text.components(separatedBy: "```").count % 2 == 1 else { return text }
        let tail = text.components(separatedBy: "\n\n").last ?? text
        var closed = text
        let ticks = tail.replacingOccurrences(of: "```", with: "").filter { $0 == "`" }.count
        if ticks % 2 == 1 { closed += "`" }
        if (tail.components(separatedBy: "**").count - 1) % 2 == 1 { closed += "**" }
        return closed
    }
}

/// Walks the parsed tree into blocks.
private struct Reader {
    let map: SourceMap
    var blocks: [ReplyDocument.Block] = []
    private var marker: String?

    init(map: SourceMap) {
        self.map = map
    }

    mutating func read(_ markup: any Markup, depth: Int, quoted: Bool) {
        switch markup {
        case let paragraph as Paragraph:
            add(.paragraph, runs: runs(in: paragraph), at: paragraph, depth: depth, quoted: quoted)
        case let heading as Heading:
            add(
                .heading(heading.level), runs: runs(in: heading), at: heading, depth: depth,
                quoted: quoted)
        case let code as CodeBlock:
            let start = codeStart(code)
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            let run = ReplyDocument.Run(text: text, style: .code, link: nil, start: start)
            add(
                .code(language: code.language), runs: [run], start: start, depth: depth,
                quoted: quoted)
        case let rule as ThematicBreak:
            add(.rule, runs: [], at: rule, depth: depth, quoted: quoted)
        case let list as UnorderedList:
            for item in list.listItems {
                readItem(item, marker: "•", depth: depth + 1, quoted: quoted)
            }
        case let list as OrderedList:
            for (index, item) in list.listItems.enumerated() {
                readItem(
                    item, marker: "\(Int(list.startIndex) + index).", depth: depth + 1,
                    quoted: quoted)
            }
        case let quote as BlockQuote:
            for child in quote.children { read(child, depth: depth, quoted: true) }
        case let table as Table:
            // On a phone a table reads best as one small block per row: its first cell in bold,
            // each other cell on a line of its own. The header's labels are left out.
            for row in table.body.rows {
                var cells: [ReplyDocument.Run] = []
                for (index, cell) in row.cells.enumerated() {
                    let text = runs(in: cell, style: index == 0 ? .strong : [])
                    guard !text.isEmpty else { continue }
                    if !cells.isEmpty {
                        cells.append(
                            ReplyDocument.Run(
                                text: "\n", style: [], link: nil, start: offset(of: cell)))
                    }
                    cells += text
                }
                add(.paragraph, runs: cells, at: row, depth: depth, quoted: quoted)
            }
        case let html as HTMLBlock:
            let run = ReplyDocument.Run(
                text: html.rawHTML, style: [], link: nil, start: offset(of: html))
            add(.paragraph, runs: [run], at: html, depth: depth, quoted: quoted)
        default:
            for child in markup.children { read(child, depth: depth, quoted: quoted) }
        }
    }

    private mutating func readItem(_ item: ListItem, marker: String, depth: Int, quoted: Bool) {
        self.marker = marker
        for child in item.children { read(child, depth: depth, quoted: quoted) }
        self.marker = nil
    }

    private mutating func add(
        _ kind: ReplyDocument.Block.Kind, runs: [ReplyDocument.Run], at markup: any Markup,
        depth: Int, quoted: Bool
    ) {
        add(kind, runs: runs, start: offset(of: markup), depth: depth, quoted: quoted)
    }

    private mutating func add(
        _ kind: ReplyDocument.Block.Kind, runs: [ReplyDocument.Run], start: Int, depth: Int,
        quoted: Bool
    ) {
        blocks.append(
            ReplyDocument.Block(
                kind: kind, depth: depth, marker: marker, quoted: quoted, runs: runs, start: start))
        marker = nil
    }

    private func runs(
        in container: any Markup, style: ReplyDocument.Style = [], link: URL? = nil
    ) -> [ReplyDocument.Run] {
        var result: [ReplyDocument.Run] = []
        for child in container.children {
            func run(_ text: String, _ style: ReplyDocument.Style, start: Int) {
                result.append(ReplyDocument.Run(text: text, style: style, link: link, start: start))
            }
            switch child {
            case let text as Markdown.Text:
                run(text.string, style, start: offset(of: text))
            case let code as InlineCode:
                // Past the opening backtick.
                run(code.code, style.union(.code), start: offset(of: code) + 1)
            case let strong as Strong:
                result += runs(in: strong, style: style.union(.strong), link: link)
            case let emphasis as Emphasis:
                result += runs(in: emphasis, style: style.union(.emphasis), link: link)
            case let strike as Strikethrough:
                result += runs(in: strike, style: style.union(.strikethrough), link: link)
            case let linked as Link:
                result += runs(
                    in: linked, style: style, link: linked.destination.flatMap(URL.init(string:)))
            case is SoftBreak:
                run(" ", style, start: offset(of: child))
            case is LineBreak:
                run("\n", style, start: offset(of: child))
            case let html as InlineHTML:
                run(html.rawHTML, style, start: offset(of: html))
            default:
                result += runs(in: child, style: style, link: link)
            }
        }
        return result
    }

    private func offset(of markup: any Markup) -> Int {
        markup.range.map { map.utf16(line: $0.lowerBound.line, column: $0.lowerBound.column) } ?? 0
    }

    /// A fenced block's code starts on the line after its fence.
    private func codeStart(_ code: CodeBlock) -> Int {
        guard let range = code.range else { return 0 }
        let fenced = map.line(range.lowerBound.line).drop { $0 == " " }
        guard fenced.hasPrefix("```") || fenced.hasPrefix("~~~") else { return offset(of: code) }
        return map.utf16(line: range.lowerBound.line + 1, column: 1)
    }
}

/// Turns the parser's locations (a line, and a column in UTF-8 bytes) into UTF-16 offsets.
private struct SourceMap {
    private let lines: [Substring]
    private let starts: [Int]
    private let length: Int

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.utf16.count + 1
        }
        self.starts = starts
        length = text.utf16.count
    }

    func line(_ number: Int) -> Substring {
        number >= 1 && number <= lines.count ? lines[number - 1] : ""
    }

    func utf16(line number: Int, column: Int) -> Int {
        guard number >= 1, number <= lines.count else { return length }
        let bytes = lines[number - 1].utf8.prefix(max(0, column - 1))
        return min(length, starts[number - 1] + String(decoding: bytes, as: UTF8.self).utf16.count)
    }
}

extension ReplyDocument {
    /// The reply as you read it, without Markdown: paragraphs apart, list items on their own lines
    /// under their markers, links as their words. For selecting and sharing text.
    public var plainText: String {
        var result = ""
        var previous: Block?
        for block in blocks {
            let text = block.kind == .rule ? "———" : block.runs.map(\.text).joined()
            let indent = String(repeating: "    ", count: max(0, block.depth - 1))
            if let previous {
                result += previous.marker != nil && block.marker != nil ? "\n" : "\n\n"
            }
            result += indent + (block.marker.map { "\($0) " } ?? "") + text
            previous = block
        }
        return result
    }
}
