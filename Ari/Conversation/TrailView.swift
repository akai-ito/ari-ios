import AriKit
import SwiftUI

/// What Ari did between its messages, on a dotted rail made of the character's own halftone dots.
/// While the turn runs, each step shows and the newest running one breathes; once it's over, each
/// run of steps folds into one line that opens again with a tap. Tap a step to see its specifics
/// in place.
struct TrailView: View {
    let trail: Trail
    let conversation: Conversation
    let reveal: Reveal
    /// The runs and steps you've opened, by ``key(run:)`` and ``key(line:)``.
    @Binding var opened: Set<String>

    var body: some View {
        let rows = rows
        let newest = rows.last { $0.isRunning }?.id
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RailRow(
                    dot: row.dot, breathing: row.id == newest, starts: index == 0,
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

        var id: String {
            switch self {
            case .note(let entry): entry.id.rawValue
            case .summary(let run, _): TrailView.key(run: run)
            case .line(let line): TrailView.key(line: line)
            }
        }

        var isRunning: Bool {
            if case .line(let line) = self { line.isRunning } else { false }
        }

        var dot: RailDot {
            switch self {
            case .note: .none
            case .summary: .done
            case .line(let line): line.isRunning ? .live : .done
            }
        }
    }

    private var rows: [Row] {
        trail.parts.flatMap { part -> [Row] in
            switch part {
            case .note(let entry):
                return [.note(entry)]
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
            let shown = reveal.position(of: entry)
            ReplyView(
                document: ReplyDocument(markdown: text),
                position: shown >= Double(text.utf16.count) ? .infinity : shown, tone: .note)
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
        case .line(let line):
            StepLineView(
                line: line,
                isOpen: Binding(
                    get: { isOpen(Self.key(line: line)) },
                    set: { _ in toggle(Self.key(line: line)) }))
        }
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
                .contentTransition(.opacity)
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
    }

    static func hasContent(_ step: Step) -> Bool {
        if step.detail != nil { return true }
        switch step.kind {
        case .thinking: return !thoughts(of: step).isEmpty
        case .webSearch: return step.query != nil || step.queries != nil || step.url != nil
        case .command: return step.command != nil
        case .fileChange: return !(step.files ?? []).isEmpty
        case .tool: return step.capability != nil || step.arguments != nil
        case .plan: return !(step.items ?? []).isEmpty
        case .imageView: return step.path != nil
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
        case .plan:
            if let explanation = step.explanation { Caption(explanation) }
            PlanChecklist(items: step.items ?? [])
        case .imageView:
            if let path = step.path { CodeBox(text: path) }
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
                    Text(url.host() ?? address).font(.caption).foregroundStyle(.ariTertiary)
                }
            }
        } else {
            Caption(address)
        }
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
