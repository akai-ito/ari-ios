import AriKit
import SwiftUI

/// One of Ari's replies, drawn from its Markdown and revealed at reading pace. A block is laid out
/// in full as soon as the reveal reaches it, with the unread rest transparent, so nothing ever
/// reflows; the leading edge fades in over a few characters instead of ticking.
struct ReplyView: View {
    let document: ReplyDocument
    /// How much is on screen, in source units; infinite once it's all shown.
    let position: Double

    /// Characters over which the leading edge fades in.
    static let edge = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks.indices, id: \.self) { index in
                let block = document.blocks[index]
                if position > Double(block.start) {
                    BlockView(block: block, position: position)
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
        return block.depth > 0 && previous.depth > 0 ? Rhythm.listItemGap : Rhythm.ariParagraphGap
    }

    /// The runs as text, each character as visible as the reveal allows.
    static func text(_ runs: [ReplyDocument.Run], position: Double, base: Font) -> AttributedString
    {
        var result = AttributedString()
        for run in runs {
            var attributes = AttributeContainer()
            attributes.font = font(for: run.style, base: base)
            if run.style.contains(.strikethrough) { attributes.strikethroughStyle = .single }
            if let link = run.link {
                attributes.link = link
                attributes.underlineStyle = .single
            }
            let fullyShown =
                position == .infinity || Double(run.start + run.text.utf16.count) + edge <= position
            if fullyShown {
                attributes.foregroundColor = .ariText
                result += AttributedString(run.text, attributes: attributes)
                continue
            }
            var offset = run.start
            for character in run.text {
                let alpha = clamp((position - Double(offset)) / edge)
                attributes.foregroundColor = Color.ariText.opacity(alpha)
                result += AttributedString(String(character), attributes: attributes)
                offset += character.utf16.count
            }
        }
        return result
    }

    private static func font(for style: ReplyDocument.Style, base: Font) -> Font {
        if style.contains(.code) { return .code }
        var font = style.contains(.strong) ? Font.ariStrong : base
        if style.contains(.emphasis) { font = font.italic() }
        return font
    }
}

private struct BlockView: View {
    let block: ReplyDocument.Block
    let position: Double

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
            item(Text(ReplyView.text(block.runs, position: position, base: .ariBody)))
        case .heading:
            item(Text(ReplyView.text(block.runs, position: position, base: .ariHeading)))
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
        let text = text.lineSpacing(Rhythm.ariLineSpacing).foregroundStyle(.ariText)
        if let marker = block.marker {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(marker)
                    .font(.ariBody.monospacedDigit())
                    .foregroundStyle(.ariTertiary)
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
