import Foundation

/// A page of memory as the Library reads it, all at once rather than revealed: Ari's freshness
/// stamps step out of the sentences, and the pages it links to are named where the words mention
/// them. Both change the runs' text, so a run's characters no longer map onto the source; a page is
/// never revealed or cut, so nothing needs them to.
extension ReplyDocument {
    /// Each "(as of 21 Oct)" leaves its sentence and ends its block as a quiet stamp.
    public func quietingStamps() -> ReplyDocument {
        var document = self
        for index in document.blocks.indices where document.blocks[index].kind == .paragraph {
            var stamps: [String] = []
            var runs: [Run] = []
            for var run in document.blocks[index].runs {
                if run.link == nil, !run.style.contains(.code) {
                    while let match = run.text.firstMatch(of: Self.stampPattern) {
                        let stamp = String(match.output.1)
                        if !stamps.contains(stamp) { stamps.append(stamp) }
                        run.text.removeSubrange(match.range)
                    }
                }
                if !run.text.isEmpty { runs.append(run) }
            }
            if let last = runs.last, !stamps.isEmpty {
                var stamp = last
                // Kept whole on its line: never "as" at the end of one and "of 26 Oct" on the next.
                stamp.text =
                    "  "
                    + stamps.joined(separator: " · ").replacingOccurrences(
                        of: " ", with: "\u{00A0}")
                stamp.style = .stamp
                stamp.link = nil
                runs.append(stamp)
            }
            document.blocks[index].runs = runs
        }
        return document
    }

    /// The first mention of each name links to its page, longest names first, so "Ali Wilson"
    /// wins over "Ali". Only plain text links: never inside a heading, code or another link.
    public func linking(_ names: [(name: String, link: URL)]) -> ReplyDocument {
        var document = self
        for (name, link) in names.sorted(by: { $0.name.count > $1.name.count }) {
            guard !name.isEmpty,
                let pattern = try? Regex(
                    "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
                ).ignoresCase()
            else { continue }
            document.linkFirst(pattern, to: link)
        }
        return document
    }

    private mutating func linkFirst(_ pattern: Regex<AnyRegexOutput>, to link: URL) {
        for index in blocks.indices where blocks[index].kind == .paragraph {
            for (position, run) in blocks[index].runs.enumerated()
            where run.link == nil && !run.style.contains(.code) && !run.style.contains(.stamp) {
                guard let match = run.text.firstMatch(of: pattern) else { continue }
                var before = run
                before.text = String(run.text[..<match.range.lowerBound])
                var linked = run
                linked.text = String(run.text[match.range])
                linked.link = link
                var after = run
                after.text = String(run.text[match.range.upperBound...])
                blocks[index].runs.replaceSubrange(
                    position...position, with: [before, linked, after].filter { !$0.text.isEmpty })
                return
            }
        }
    }

    private static var stampPattern: Regex<(Substring, Substring)> { #/\s*\((as of [^)]+)\)/# }
}
