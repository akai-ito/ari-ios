import Foundation
import Markdown

/// A page as the Library lays it out: its words, with the photos it keeps standing where the
/// Markdown shows them.
public enum PagePiece: Sendable, Equatable {
    /// Blocks of words, drawn as one reading.
    case words(ReplyDocument)
    /// Photos side by side in the story, one or more.
    case photos([PagePhoto])
}

/// A photo where the page shows it, with the words that say what it shows.
public struct PagePhoto: Sendable, Equatable, Identifiable {
    public let photo: MemoryPhoto
    /// What it shows, from the Markdown: for VoiceOver, and in place of a photo that won't load.
    public let alt: String
    /// Its place among the page's photos, as the same photo can show twice.
    public let id: Int

    public init(photo: MemoryPhoto, alt: String, id: Int) {
        self.photo = photo
        self.alt = alt
        self.id = id
    }
}

extension ReplyDocument {
    /// `reading`, the page's words as the Library reads them, with the photos memory keeps put in:
    /// a paragraph that only shows photos becomes them, and a photo amid words comes just after
    /// its paragraph. An image memory doesn't keep, such as one on the web, stays as its words.
    public static func pieces(of page: MemoryPage, reading: ReplyDocument) -> [PagePiece] {
        guard !page.photos.isEmpty else { return [.words(reading)] }
        let found = PhotoFinder.paragraphs(in: page)
        var pieces: [PagePiece] = []
        var words: [Block] = []
        func endWords() {
            guard !words.isEmpty else { return }
            var part = reading
            part.blocks = words
            pieces.append(.words(part))
            words = []
        }
        func add(_ photos: [PagePhoto]) {
            endWords()
            if case .photos(let before) = pieces.last {
                pieces[pieces.count - 1] = .photos(before + photos)
            } else {
                pieces.append(.photos(photos))
            }
        }
        for block in reading.blocks {
            guard block.kind == .paragraph, let paragraph = found[block.start] else {
                words.append(block)
                continue
            }
            if !paragraph.onlyPhotos { words.append(block) }
            add(paragraph.photos)
        }
        endWords()
        return pieces
    }
}

/// Finds the paragraphs that show photos memory keeps, by where each starts in the source, the
/// same way a reading's blocks know it.
private enum PhotoFinder {
    struct Paragraph {
        var photos: [PagePhoto]
        /// Nothing but photos and the space between them.
        var onlyPhotos: Bool
    }

    static func paragraphs(in page: MemoryPage) -> [Int: Paragraph] {
        let kept = Dictionary(
            page.photos.map { ($0.source, $0) }, uniquingKeysWith: { first, _ in first })
        let map = SourceMap(page.markdown)
        var found: [Int: Paragraph] = [:]
        var count = 0
        func visit(_ markup: any Markup) {
            guard let paragraph = markup as? Markdown.Paragraph else {
                for child in markup.children { visit(child) }
                return
            }
            var photos: [PagePhoto] = []
            var onlyPhotos = true
            func read(_ inline: any Markup) {
                switch inline {
                case let image as Markdown.Image:
                    if let source = image.source, let photo = kept[source] {
                        photos.append(PagePhoto(photo: photo, alt: image.plainText, id: count))
                        count += 1
                    } else {
                        onlyPhotos = false
                    }
                case let text as Markdown.Text:
                    if !text.string.allSatisfy(\.isWhitespace) { onlyPhotos = false }
                case is SoftBreak, is LineBreak:
                    break
                default:
                    onlyPhotos = false
                    for child in inline.children { read(child) }
                }
            }
            for child in paragraph.children { read(child) }
            guard !photos.isEmpty, let range = paragraph.range else { return }
            let start = map.utf16(line: range.lowerBound.line, column: range.lowerBound.column)
            found[start] = Paragraph(photos: photos, onlyPhotos: onlyPhotos)
        }
        visit(Document(parsing: page.markdown, options: .disableSmartOpts))
        return found
    }
}
