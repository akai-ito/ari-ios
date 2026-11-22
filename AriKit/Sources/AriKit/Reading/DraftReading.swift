import Foundation

/// A draft's words as Mail shows them. Kumo writes drafts in light Markdown, and the card draws
/// inline formatting (bold, italics, links) itself; what it can't draw is made plain here, so the
/// card never shows Markdown's marks: a picture leaves the words (the draft's `attachments` lists
/// it), a list's item gets a bullet, a heading reads bold and a quote loses its marker.
public enum DraftReading {
    public static func readable(_ markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let pictureless = String(line).replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
                // A line that held only a picture goes with it.
                if pictureless.allSatisfy(\.isWhitespace), !line.allSatisfy(\.isWhitespace) {
                    return nil
                }
                if let item = pictureless.wholeMatch(of: /(\s*)[-*+]\s+(.*)/) {
                    return "\(item.output.1)• \(item.output.2)"
                }
                if let heading = pictureless.wholeMatch(of: /#{1,6}\s+(.*)/) {
                    return "**\(heading.output.1)**"
                }
                if let quote = pictureless.wholeMatch(of: />\s?(.*)/) {
                    return String(quote.output.1)
                }
                return pictureless
            }
            .joined(separator: "\n")
    }
}

extension DraftCard {
    /// The words as Mail shows them, without Markdown's marks; see ``DraftReading``.
    public var readableBody: String { DraftReading.readable(body) }
}
