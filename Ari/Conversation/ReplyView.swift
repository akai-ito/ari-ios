import AriKit
import SwiftUI

/// One of Ari's messages, drawn from its Markdown and revealed at reading pace. A block is laid out
/// in full as soon as the reveal reaches it, with the unread rest transparent, so nothing ever
/// reflows; the leading edge fades in over a few characters instead of ticking.
struct ReplyView: View {
    let document: ReplyDocument
    /// How much is on screen, in source units; infinite once it's all shown.
    let position: Double
    var tone = Tone.reply

    /// A reply is Ari's answer, in its white serif: the only serif in the conversation. A note is
    /// what it says along the way, a whisper on the trail: small upright grey sans, the size of the
    /// steps around it, so it never competes with the answer.
    enum Tone {
        case reply, note

        var color: Color { self == .reply ? .ariText : .ariSecondary }
        var body: Font { self == .reply ? .ariBody : .footnote }
        var strong: Font { self == .reply ? .ariStrong : .footnote.weight(.semibold) }
        var heading: Font { self == .reply ? .ariHeading : .footnote.weight(.semibold) }
        var lineSpacing: CGFloat { self == .reply ? Rhythm.ariLineSpacing : 2 }
        var paragraphGap: CGFloat { self == .reply ? Rhythm.ariParagraphGap : 6 }
    }

    /// Characters over which the leading edge fades in.
    static let edge = 10.0

    var body: some View {
        let shapes = document.shapes
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks.indices, id: \.self) { index in
                let block = document.blocks[index]
                if position > Double(block.start) {
                    // A block fully on screen gets a position that no longer changes, so only the
                    // block being revealed redraws as the reveal moves on.
                    let end = block.runs.last.map { $0.start + $0.text.utf16.count } ?? block.start
                    BlockView(
                        block: block,
                        position: position >= Double(end) + Self.edge ? .infinity : position,
                        tone: tone,
                        shape: shapes[index]
                    )
                    .padding(.top, index == 0 ? 0 : gap(before: index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// List items sit close together; everything else gets a paragraph's room.
    private func gap(before index: Int) -> CGFloat {
        let block = document.blocks[index]
        let previous = document.blocks[index - 1]
        return block.depth > 0 && previous.depth > 0 ? Rhythm.listItemGap : tone.paragraphGap
    }

    /// The runs as text, each character as visible as the reveal allows.
    static func text(
        _ runs: [ReplyDocument.Run], position: Double, base: Font, tone: Tone = .reply
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var attributes = AttributeContainer()
            attributes.font = font(for: run.style, base: base, strong: tone.strong)
            if run.style.contains(.strikethrough) { attributes.strikethroughStyle = .single }
            if let link = run.link {
                attributes.link = link
                // Another page of memory is a quiet dotted line; the web, a full one.
                attributes.underlineStyle =
                    link.scheme == PageLink.scheme ? Text.LineStyle(pattern: .dot) : .single
            }
            let fullyShown =
                position == .infinity || Double(run.start + run.text.utf16.count) + edge <= position
            if fullyShown {
                attributes.foregroundColor = run.style.contains(.stamp) ? .ariTertiary : tone.color
                result += AttributedString(run.text, attributes: attributes)
                continue
            }
            // Shown in one piece, the leading edge character by character as it fades in, and the
            // unread rest in one piece: a piece per character made long paragraphs costly to lay
            // out on every frame.
            var offset = run.start
            var piece = ""
            var pieceAlpha = -1.0
            func flush() {
                guard !piece.isEmpty else { return }
                attributes.foregroundColor = tone.color.opacity(pieceAlpha)
                result += AttributedString(piece, attributes: attributes)
                piece = ""
            }
            for character in run.text {
                let alpha = clamp((position - Double(offset)) / edge)
                if alpha != pieceAlpha || (alpha > 0 && alpha < 1) {
                    flush()
                    pieceAlpha = alpha
                }
                piece.append(character)
                offset += character.utf16.count
            }
            flush()
        }
        return result
    }

    private static func font(for style: ReplyDocument.Style, base: Font, strong: Font) -> Font {
        if style.contains(.code) { return .code }
        if style.contains(.stamp) { return .caption }
        var font = style.contains(.strong) ? strong : base
        if style.contains(.emphasis) { font = font.italic() }
        return font
    }
}

private struct BlockView: View {
    let block: ReplyDocument.Block
    let position: Double
    let tone: ReplyView.Tone
    /// An `ari:` block's shape: `.some(nil)` if it doesn't read.
    var shape: ReplyShape??

    var body: some View {
        content
            .padding(.leading, CGFloat(max(0, block.depth - 1)) * 18)
            .padding(.leading, block.quoted ? 14 : 0)
            .overlay(alignment: .leading) {
                if block.quoted {
                    Rectangle().fill(.ariLine).frame(width: 2)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .paragraph:
            item(Text(ReplyView.text(block.runs, position: position, base: tone.body, tone: tone)))
        case .heading:
            item(
                Text(ReplyView.text(block.runs, position: position, base: tone.heading, tone: tone))
            )
        case .code where shape != nil:
            // Drawn once it's all here; a quiet card while Ari writes it; its text if it never
            // reads.
            if let drawn = shape ?? nil, position == .infinity {
                ShapeView(shape: drawn)
            } else if position != .infinity {
                ShapePlaceholder()
            } else {
                CodeBlockView(
                    language: nil, code: block.runs.first?.text ?? "",
                    text: Text(ReplyView.text(block.runs, position: position, base: .code)))
            }
        case .code(let language):
            CodeBlockView(
                language: language, code: block.runs.first?.text ?? "",
                text: Text(ReplyView.text(block.runs, position: position, base: .code)))
        case .rule:
            Rectangle().fill(.ariLine).frame(height: 1).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func item(_ text: Text) -> some View {
        let text = text.lineSpacing(tone.lineSpacing).foregroundStyle(tone.color)
        if let marker = block.marker {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                switch marker {
                case "☐", "☑":
                    // A task list's item, done or not.
                    Image(systemName: marker == "☑" ? "checkmark.square" : "square")
                        .font(tone.body)
                        .foregroundStyle(.ariTertiary)
                        .accessibilityLabel(marker == "☑" ? "Done" : "Not done")
                default:
                    Text(marker)
                        .font(tone.body.monospacedDigit())
                        .foregroundStyle(.ariTertiary)
                }
                text
            }
        } else {
            text
        }
    }
}

/// A code block: a thin outlined box with its language and Copy, there from its first line, so it
/// never changes shape as the code arrives. Copy gives the code alone.
struct CodeBlockView: View {
    let language: String?
    let code: String
    let text: Text

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language ?? "")
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                Spacer()
                Button {
                    Pasteboard.copy(code)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Text(copied ? "Copied" : "Copy")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? .ariTertiary : .ariText)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                text.lineSpacing(2).fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                .ariLine, lineWidth: 1))
    }
}
