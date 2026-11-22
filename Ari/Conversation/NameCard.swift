import AriKit
import SwiftUI

/// A name Kumo keeps, in a small card: who or what it is, a few things worth knowing now, its page,
/// and a way to ask about it. A tapped name in a reply opens it above the words; `ari:person`
/// shows it in place.
struct NameCardContent: View {
    let name: NameLink
    /// Closes the card, when it floats over the chat.
    var dismiss: (() -> Void)?

    @Environment(Memory.self) private var memory: Memory?
    @Environment(Motions.self) private var motions: Motions?
    @Environment(MadePages.self) private var made: MadePages?
    @Environment(\.replyActions) private var actions
    @Environment(\.askKumo) private var askKumo
    @Environment(\.motionOpener) private var opener
    @State private var page: MemoryPage?
    @State private var problem: String?
    @State private var opensPage = false
    @State private var opensMade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let card {
                HStack(spacing: 12) {
                    NameMonogram(letter: card.letter, symbol: card.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title).font(.ariName).foregroundStyle(.ariText)
                        if let subtitle = card.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.ariSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                if !card.facts.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(card.facts, id: \.label) { fact in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(fact.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.ariTertiary)
                                    .frame(width: 58, alignment: .leading)
                                Text(fact.value)
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(.ariText)
                                    .lineLimit(3)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                WrappingStack(spacing: 8) {
                    DeskPill(title: card.open, acts: true, action: open)
                    if let ask = card.ask, let send = actions.choose ?? askKumo {
                        DeskPill(title: "Ask about \(card.short)") {
                            dismiss?()
                            send(ask)
                        }
                    }
                }
            } else if let problem {
                Text(problem).font(.footnote).foregroundStyle(.ariSecondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: name) { await load() }
        .sheet(isPresented: $opensPage) {
            if case .memory(let address) = name {
                NavigationStack {
                    PageView(memory: memory, address: address)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { opensPage = false }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $opensMade) {
            if case .made(let id) = name { MadePageView(id: id) }
        }
    }

    private func load() async {
        guard case .memory(let address) = name, page == nil else { return }
        guard let memory else {
            problem = "Connect to your server to see who this is."
            return
        }
        do throws(RequestError) {
            page = try await memory.page(address)
        } catch {
            problem =
                error.status == 404
                ? "\(LeadName.current) doesn't keep a page about this any more."
                : "Couldn't load this: \(error.plainWords)"
        }
    }

    private func open() {
        switch name {
        case .memory:
            opensPage = true
        case .motion(let motion):
            dismiss?()
            opener.open?(motion, "name \(motion.rawValue)")
        case .made:
            opensMade = true
        }
    }

    /// What the card says, once it knows.
    private var card: NameCardReading? {
        switch name {
        case .memory:
            page.map(NameCardReading.init(page:))
        case .motion(let id):
            motions?[id].map(NameCardReading.init(motion:))
        case .made(let id):
            made?[id].map(NameCardReading.init(made:))
        }
    }
}

/// A name's card, as words: its title and who or what it is, a few facts, and its buttons.
struct NameCardReading {
    struct Fact {
        let label: String
        let value: String
    }

    let title: String
    let subtitle: String?
    let facts: [Fact]
    let letter: String?
    let symbol: String?
    /// The page's button: "Maya's page", "Open".
    let open: String
    /// What "Ask about…" sends, if it offers one.
    let ask: String?
    /// The name, short, for "Ask about Maya".
    let short: String

    init(page: MemoryPage) {
        title = page.title
        short =
            page.shelf == "people"
            ? String(page.title.split(separator: " ").first ?? "") : page.title
        let lately = Self.firstSentence(page.markdown)
        subtitle = page.gist ?? LibraryHome.title(ofShelf: page.shelf)
        facts = [
            lately.map { Fact(label: "Lately", value: $0) },
            Fact(
                label: "As of",
                value: page.changedAt.date.formatted(.relative(presentation: .named))),
        ].compactMap(\.self)
        letter =
            page.shelf == "people" || page.shelf == "groups" ? String(page.title.prefix(1)) : nil
        symbol = letter == nil ? ShelfGlyph.symbol(for: page.shelf) : nil
        open = page.shelf == "people" ? "\(short)'s page" : "Open page"
        ask = "Tell me about \(page.title)."
    }

    init(motion: Motion) {
        title = motion.title
        short = motion.title
        subtitle = motion.kind.rawValue.prefix(1).uppercased() + motion.kind.rawValue.dropFirst()
        facts = [
            motion.summary.isEmpty ? nil : Fact(label: "Now", value: motion.summary),
            Fact(
                label: "Changed",
                value: motion.changedAt.date.formatted(.relative(presentation: .named))),
        ].compactMap(\.self)
        letter = nil
        symbol = MotionSymbol.name(for: motion.kind)
        open = "Open"
        ask = "How's \(motion.title) going?"
    }

    init(made: Made) {
        title = made.title
        short = made.title
        subtitle = "A page \(LeadName.current) made"
        facts = [
            made.summary.isEmpty ? nil : Fact(label: "In it", value: made.summary),
            made.forDay.flatMap(MadeLook.day).map { Fact(label: "For", value: $0) },
            Fact(
                label: made.version > 1 ? "Updated" : "Made",
                value: made.changedAt.date.formatted(.relative(presentation: .named))),
        ].compactMap(\.self)
        letter = nil
        symbol = "doc.richtext.fill"
        open = "Open"
        ask = nil
    }

    /// The page's present in its first sentence: what's going on, at a glance.
    static func firstSentence(_ markdown: String) -> String? {
        let plain = ReplyDocument(markdown: markdown).withoutShapes.blocks
            .first { block in
                if case .paragraph = block.kind { true } else { false }
            }
            .map { $0.runs.map(\.text).joined() }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plain, !plain.isEmpty else { return nil }
        let end =
            plain.firstIndex { ".!?".contains($0) }.map { plain.index(after: $0) } ?? plain.endIndex
        let sentence = String(plain[..<end])
        return sentence.count > 140 ? String(sentence.prefix(139)) + "…" : sentence
    }
}

/// A person's initial in Kumo's bone dots on a faint disc, as in the Library, or a symbol for a
/// place, a pursuit or a page.
struct NameMonogram: View {
    let letter: String?
    let symbol: String?
    var side: CGFloat = 46

    var body: some View {
        if let letter {
            ZStack {
                Dots(step: 3.4 * side / 46, size: 0.34).opacity(0.22)
                Dots(step: 2.0 * side / 46, size: 0.44)
                    .mask {
                        Text(letter.uppercased())
                            .font(.system(size: 26 * side / 46, weight: .black, design: .serif))
                    }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        } else {
            DotGlyph(symbol: symbol ?? "circle.fill", side: side)
        }
    }
}

extension EnvironmentValues {
    /// Sends a message to Kumo, from anywhere, such as "Ask about Maya" on a name's card.
    @Entry var askKumo: ((String) -> Void)?
}

extension View {
    /// Opens a name's card when a name Kumo keeps is tapped in the words; any other link opens as
    /// it would have.
    func opensNames() -> some View {
        modifier(OpensNames())
    }
}

private struct OpensNames: ViewModifier {
    @Environment(\.openURL) private var upstream
    @State private var shown: NameLink?

    func body(content: Content) -> some View {
        content
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if let name = NameLink(url) {
                        shown = name
                        return .handled
                    }
                    upstream(url)
                    return .handled
                }
            )
            .popover(item: $shown) { name in
                NameCardContent(name: name) { shown = nil }
                    .padding(16)
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Color.ariSurface)
            }
    }
}
