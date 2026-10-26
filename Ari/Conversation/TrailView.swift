import AriKit
import SwiftUI

/// What Ari did between its messages, on a dotted rail made of the character's own halftone dots.
/// While the turn runs, each step shows and the newest running one breathes; once it's over, each
/// run of steps folds into one line that opens again with a tap. Tap a step to see its specifics
/// in place.
struct TrailView: View {
    let trail: Trail
    let conversation: Conversation
    let reveal: RevealModel
    /// The runs and steps you've opened, by ``key(run:)`` and ``key(line:)``.
    @Binding var opened: Set<String>
    /// You tapped one of an ask's options.
    var answer: (Ask, Ask.Option) -> Void = { _, _ in }

    var body: some View {
        let rows = rows
        let newest = rows.last { $0.isRunning || isWaiting($0) }?.id
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RailRow(
                    dot: isWaiting(row) ? .live : row.dot, breathing: row.id == newest,
                    starts: index == 0,
                    continues: index < rows.count - 1
                ) {
                    content(for: row)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: rows.map(\.id))
    }

    static func key(run: StepRun) -> String { "run " + run.id }
    static func key(line: StepLine) -> String { "line " + line.id }

    // MARK: - Rows

    private enum Row: Identifiable {
        case note(Conversation.Entry)
        case summary(StepRun, isOpen: Bool)
        case line(StepLine)
        case ask(Ask)

        var id: String {
            switch self {
            case .note(let entry): entry.id.rawValue
            case .summary(let run, _): TrailView.key(run: run)
            case .line(let line): TrailView.key(line: line)
            case .ask(let ask): "ask " + ask.id.rawValue
            }
        }

        var isRunning: Bool {
            if case .line(let line) = self { line.isRunning } else { false }
        }

        var dot: RailDot {
            switch self {
            case .note: .none
            case .summary, .ask: .done
            case .line(let line): line.isRunning ? .live : .done
            }
        }
    }

    private var rows: [Row] {
        trail.parts.flatMap { part -> [Row] in
            switch part {
            case .note(let entry):
                return [.note(entry)]
            case .ask(let ask):
                return [.ask(ask)]
            case .steps(let run):
                guard run.isFolded else { return run.lines.map(Row.line) }
                let isOpen = isOpen(Self.key(run: run))
                return [.summary(run, isOpen: isOpen)] + (isOpen ? run.lines.map(Row.line) : [])
            }
        }
    }

    @ViewBuilder
    private func content(for row: Row) -> some View {
        switch row {
        case .note(let entry):
            let text = conversation.visibleText(of: entry)
            let document = ReplyDocument(markdown: text)
            Paced(shown: reveal.shown(entry), length: text.utf16.count) { position in
                ReplyView(document: document, position: position, tone: .note)
            }
        case .summary(let run, let isOpen):
            Button {
                withAnimation(.smooth(duration: 0.35)) { toggle(Self.key(run: run)) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(run.summary)
                        .multilineTextAlignment(.leading)
                    Chevron(isOpen: isOpen)
                }
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Folds the steps" : "Shows each step")
        case .ask(let ask):
            AskView(ask: ask, settling: conversation.settling[ask.id]) { option in
                answer(ask, option)
            }
        case .line(let line):
            StepLineView(
                line: line,
                isOpen: Binding(
                    get: { isOpen(Self.key(line: line)) },
                    set: { _ in toggle(Self.key(line: line)) }))
        }
    }

    /// An ask that waits for your answer, lit like a running step.
    private func isWaiting(_ row: Row) -> Bool {
        guard case .ask(let ask) = row else { return false }
        return ask.outcome == nil && conversation.settling[ask.id] == nil
    }

    private func isOpen(_ key: String) -> Bool {
        #if DEBUG
            if DebugScript.opensTrail { return true }
        #endif
        return opened.contains(key)
    }

    private func toggle(_ key: String) {
        if opened.contains(key) { opened.remove(key) } else { opened.insert(key) }
    }
}

/// A step's dot on the rail: bone while it runs, dusky once done; a note has none.
enum RailDot { case live, done, none }

/// A row on the trail, with the rail down its left and, for a step, its dot.
struct RailRow<Content: View>: View {
    let dot: RailDot
    var breathing = false
    let starts: Bool
    let continues: Bool
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    TimelineView(.animation(paused: !breathing || reduceMotion)) { context in
                        rail(at: context.date.timeIntervalSinceReferenceDate)
                    }
                    .frame(width: 14, height: proxy.size.height + (continues ? 16 : 0))
                }
                .accessibilityHidden(true)
            }
    }

    private func rail(at t: Double) -> some View {
        Canvas { context, size in
            let x = 6.0
            var y = starts ? (dot == .none ? 4.0 : 9.0) : -8.0
            let end = continues ? size.height : (dot == .none ? size.height - 4 : 9.0)
            while y <= end {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)),
                    with: .color(Color.ariTertiary.opacity(0.7)))
                y += 4.5
            }
            guard dot != .none else { return }
            let live = dot == .live
            let breath = breathing && !reduceMotion ? 0.5 * sin(t * 3.5) : 0
            let radius = live ? 3.6 + breath : 3.2
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: x - radius, y: 9 - radius, width: radius * 2, height: radius * 2)),
                with: .color(live ? Color.ariBone : Color.ariDusk))
        }
    }
}

/// A step, or similar steps in a row: present tense while it runs, past tense once done. While it
/// runs, one line of specifics sits underneath (and a plan shows its checklist); tapped, it opens
/// to show everything about it.
private struct StepLineView: View {
    let line: StepLine
    @Binding var isOpen: Bool

    var body: some View {
        let opens = line.steps.contains(where: StepDetails.hasContent)
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if opens {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { isOpen.toggle() }
                    } label: {
                        title(chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")
                } else {
                    // Nothing more to show, so it's only words: a disabled button would grey them.
                    title(chevron: false)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: line.title)

            if let specifics = line.specifics, !isOpen {
                Text(specifics)
                    .font(.caption.monospaced())
                    .foregroundStyle(.ariTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if line.isRunning, !isOpen, let items = line.steps.first?.items {
                PlanChecklist(items: items)
            }
            if isOpen {
                StepDetails(steps: line.steps)
                    .transition(.opacity)
            }
        }
    }

    private func title(chevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(line.title)
                .multilineTextAlignment(.leading)
                // The words change in place as the tense does; a cross-fade showed both titles
                // on top of each other mid-change ("Searching the web" over "2 times").
                .contentTransition(.interpolate)
            if let mark = line.mark { Tag(text: mark) }
            if chevron { Chevron(isOpen: isOpen) }
        }
        .font(.footnote)
        .foregroundStyle(.ariSecondary)
        .contentShape(Rectangle())
    }
}

/// Everything about a step, in place under its title.
private struct StepDetails: View {
    let steps: [Step]

    @Environment(Memory.self) private var memory: Memory?
    @State private var openedPage: PageAddress?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in
                VStack(alignment: .leading, spacing: 6) {
                    if steps.count > 1 {
                        Text(step.title).font(.caption).foregroundStyle(.ariSecondary)
                    }
                    details(of: step)
                    footer(of: step)
                }
            }
        }
        .padding(.top, 4)
        .sheet(item: $openedPage) { address in
            NavigationStack {
                PageView(memory: memory, address: address)
                    .navigationDestination(for: PageAddress.self) {
                        PageView(memory: memory, address: $0)
                    }
            }
            .tint(.ariText)
        }
    }

    static func hasContent(_ step: Step) -> Bool {
        if step.detail != nil { return true }
        switch step.kind {
        case .thinking: return !thoughts(of: step).isEmpty
        case .webSearch: return step.query != nil || step.queries != nil || step.url != nil
        case .command: return step.command != nil
        case .fileChange: return !(step.files ?? []).isEmpty
        case .tool: return step.capability != nil || step.arguments != nil || step.url != nil
        case .plan: return !(step.items ?? []).isEmpty
        case .imageView: return step.path != nil
        case .memory:
            return step.memoryAction == .updated ? step.change != nil : !(step.pages ?? []).isEmpty
        default: return false
        }
    }

    /// The summary of Ari's thinking, without the bold heading it opens with, already the title.
    static func thoughts(of step: Step) -> String {
        var text = step.summary ?? ""
        if let heading = step.heading, text.hasPrefix("**\(heading)**") {
            text.removeFirst("**\(heading)**".count)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func details(of step: Step) -> some View {
        switch step.kind {
        case .thinking:
            ReplyView(
                document: ReplyDocument(markdown: Self.thoughts(of: step)), position: .infinity,
                tone: .note)
        case .webSearch:
            ForEach(step.queries ?? step.query.map { [$0] } ?? [], id: \.self) { query in
                Caption("“\(query)”")
            }
            if let pattern = step.pattern { Caption("Looked for “\(pattern)”") }
            if let url = step.url { WebLink(title: nil, address: url) }
            ForEach(step.results ?? [], id: \.url) { result in
                WebLink(title: result.title, address: result.url)
            }
        case .command:
            if let command = step.command { CodeBox(text: command) }
            if let output = step.output, !output.isEmpty { CodeBox(text: output, scrolls: true) }
            if let code = step.exitCode, code != 0 { Caption("Exited with code \(code)") }
        case .fileChange:
            ForEach(step.files ?? [], id: \.path) { file in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(file.path).font(.caption.monospaced()).foregroundStyle(.ariSecondary)
                    Caption(Self.change(file))
                }
            }
        case .tool:
            Caption([step.capability, step.operation].compactMap { $0 }.joined(separator: " · "))
            if let arguments = step.arguments { CodeBox(text: arguments) }
            // What the tool made, such as the issue a gap report filed.
            if let url = step.url { WebLink(title: nil, address: url) }
        case .plan:
            if let explanation = step.explanation { Caption(explanation) }
            PlanChecklist(items: step.items ?? [])
        case .imageView:
            if let path = step.path { CodeBox(text: path) }
        case .memory:
            // An update shows what changed, fetched now: the trail never carries a page's words.
            if step.memoryAction == .updated, let change = step.change {
                PageChangeView(memory: memory, change: change)
            }
            if step.memoryAction != .updated {
                ForEach(step.pages ?? []) { page in
                    if page.address.isPage {
                        Button(page.title + " ›") { openedPage = page.address }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.ariSecondary)
                    } else {
                        Caption(page.title)
                    }
                }
            } else if let page = step.pages?.first {
                Button("Open \(page.title) ›") { openedPage = page.address }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.ariSecondary)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func footer(of step: Step) -> some View {
        if let detail = step.detail {
            Text(detail).font(.caption).foregroundStyle(.ariSecondary)
        }
        if let ms = step.durationMs, ms >= 1000 {
            Caption(
                "Took \((Double(ms) / 1000).formatted(.number.precision(.fractionLength(0...1)))) s"
            )
        }
    }

    private static func change(_ file: Step.FileChange) -> String {
        var words: [String] =
            switch file.change {
            case .added: ["added"]
            case .deleted: ["deleted"]
            case .moved: ["moved" + (file.from.map { " from \($0)" } ?? "")]
            default: []
            }
        if let added = file.linesAdded, let removed = file.linesRemoved {
            words.append("+\(added) −\(removed)")
        }
        return words.joined(separator: " · ")
    }
}

/// A plan's items, each with where it stands.
private struct PlanChecklist: View {
    let items: [Step.PlanItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.symbol(item.state))
                        .font(.caption2)
                        .accessibilityLabel(Self.state(item.state))
                    Text(item.text).font(.caption)
                }
                .foregroundStyle(item.state == .done ? .ariTertiary : .ariSecondary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private static func symbol(_ state: PlanItemState) -> String {
        switch state {
        case .done: "checkmark.circle"
        case .inProgress: "circle.lefthalf.filled"
        default: "circle"
        }
    }

    private static func state(_ state: PlanItemState) -> String {
        switch state {
        case .done: "Done"
        case .inProgress: "In progress"
        default: "To do"
        }
    }
}

/// Monospaced text in a quiet box: a command, its output, a tool's arguments. Long output scrolls
/// inside the box, so it never takes over the conversation.
private struct CodeBox: View {
    let text: String
    var scrolls = false

    var body: some View {
        let label = Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.ariSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        Group {
            if scrolls, text.split(separator: "\n", omittingEmptySubsequences: false).count > 8 {
                ScrollView { label }
                    .frame(height: 150)
                    .defaultScrollAnchor(.bottom)
            } else {
                label
            }
        }
        .background(.ariSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WebLink: View {
    let title: String?
    let address: String

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 1) {
                    if let title { Text(title).font(.caption).foregroundStyle(.ariText) }
                    Text(Self.label(url) ?? address).font(.caption).foregroundStyle(.ariTertiary)
                }
            }
        } else {
            Caption(address)
        }
    }
}

extension WebLink {
    /// Where a link goes, briefly: "akai-ito/ito-core #42" for a GitHub issue or pull request,
    /// otherwise the site.
    static func label(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host() == "github.com", parts.count == 4, ["issues", "pull"].contains(parts[2]) {
            return "\(parts[0])/\(parts[1]) #\(parts[3])"
        }
        return url.host()
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.ariTertiary)
    }
}

private struct Chevron: View {
    let isOpen: Bool

    var body: some View {
        Text("›")
            .foregroundStyle(.ariTertiary)
            .rotationEffect(isOpen ? .degrees(90) : .zero)
            .accessibilityHidden(true)
    }
}

/// Something Ari asked you. While it waits, the question is Ari's own words to you (the serif, full
/// colour), with its options to tap, and room to type below; the option that goes ahead is filled
/// like Send. Once answered or cancelled, it settles into a quiet line on the trail, and your answer
/// is your own message below it.
private struct AskView: View {
    let ask: Ask
    let settling: Conversation.Settling?
    let answer: (Ask.Option) -> Void

    var body: some View {
        if ask.outcome == nil && settling == nil {
            open
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Asked: \(ask.question)")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                if ask.outcome == .cancelled || settling == .cancelling {
                    Tag(text: "Stopped before you answered")
                }
            }
        }
    }

    private var open: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ask.question)
                .font(.ariBody)
                .foregroundStyle(.ariText)
                .lineSpacing(Rhythm.ariLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
            if let preview = ask.preview {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.ariSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.ariSurface, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.ariLine, lineWidth: 1)
                    }
                    .textSelection(.enabled)
            }
            if !ask.options.isEmpty {
                WrappingStack(spacing: 8) {
                    ForEach(ask.options, id: \.label) { option in
                        OptionButton(option: option) { answer(option) }
                    }
                }
                let described = ask.options.filter { $0.description != nil }
                if !described.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(described, id: \.label) { option in
                            Text("\(option.label): \(option.description ?? "")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.ariTertiary)
            }
        }
        .padding(.top, 1)
    }

    private var hint: String? {
        if ask.secret { return "Type it below. It stays out of your history in Ari." }
        if ask.options.isEmpty { return "Type your answer below." }
        return ask.allowsText ? "Or type your own answer." : nil
    }
}

/// An option under an ask: outlined, in your hand (SF Pro), or filled like Send when it's the
/// option that goes ahead.
private struct OptionButton: View {
    let option: Ask.Option
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(option.label)
                .font(.subheadline.weight(option.acts ? .semibold : .regular))
                .foregroundStyle(option.acts ? Color.ariBackground : .ariText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if option.acts {
                        Capsule().fill(.ariText)
                    } else {
                        Capsule().strokeBorder(.ariLine, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lays its views out in rows, starting a new row when the next one wouldn't fit.
private struct WrappingStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
