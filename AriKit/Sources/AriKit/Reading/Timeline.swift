import Foundation

/// The conversation as it reads, top to bottom: your messages and Ari's answers, and between them the
/// trail of what Ari did along the way. Messages and steps are merged by position, so each step sits
/// exactly where it happened.
///
/// A trail holds runs of steps and Ari's short notes. A note long enough to read as an answer (a
/// poem, a list) stands as a message of its own, and the trail carries on after it. While its turn
/// runs, a trail shows each step; once the turn is over, each run of steps folds into one line. A
/// step waits until the note or reply before it is fully on screen, so it never appears under
/// half-shown text.
public struct Timeline: Equatable, Sendable {
    public private(set) var items: [Item] = []

    public enum Item: Equatable, Sendable, Identifiable {
        /// Yours, a reply, or a note that reads as an answer.
        case message(Conversation.Entry)
        case trail(Trail)

        public var id: String {
            switch self {
            case .message(let entry): entry.id.rawValue
            case .trail(let trail): trail.id
            }
        }
    }

    public init(_ conversation: Conversation, reveal: Reveal, at now: Date = .now) {
        let liveTurn = conversation.turn?.id
        // The first of Ari's messages still being revealed: steps after it wait.
        let held = conversation.entries.first {
            Reveal.paces($0) && $0.position != nil
                && reveal.position(of: $0, at: now)
                    < Double(conversation.visibleText(of: $0).utf16.count)
        }?.position

        var trail: Trail?
        func close() {
            if let finished = trail, !finished.parts.isEmpty {
                items.append(.trail(finished.folding(live: finished.turn == liveTurn)))
            }
            trail = nil
        }
        func add(_ part: Trail.Added, turn: TurnID) {
            if trail?.turn != turn { close() }
            if trail == nil { trail = Trail(turn: turn) }
            trail?.add(part, live: turn == liveTurn)
        }

        for piece in Self.merged(conversation) {
            switch piece {
            case .entry(let entry):
                if Self.isAside(entry), let turn = entry.turn {
                    add(.note(entry), turn: turn)
                } else if entry.isShown || Self.isNote(entry) {
                    close()
                    items.append(.message(entry))
                }
            case .step(let step):
                guard Self.isOnTrail(step), held.map({ step.position < $0 }) ?? true else {
                    continue
                }
                add(.step(step), turn: step.turn)
            }
        }
        close()
    }

    /// A note that's only progress ("Checking what people say."): one short line, which hangs on
    /// the trail. A longer one, or one with lines of its own, is something you asked for.
    public static func isAside(_ entry: Conversation.Entry) -> Bool {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isNote(entry) && !text.contains("\n") && text.count <= 160
    }

    static func isNote(_ entry: Conversation.Entry) -> Bool {
        entry.role == .agent && entry.kind == .note
    }

    /// Thinking shows only once it has a heading of its own; until then the character and the
    /// status line say Ari is thinking.
    static func isOnTrail(_ step: Step) -> Bool {
        step.kind != .thinking || !(step.heading ?? "").isEmpty
    }

    private enum Piece {
        case entry(Conversation.Entry)
        case step(Step)

        var position: Int? {
            switch self {
            case .entry(let entry): entry.position
            case .step(let step): step.position
            }
        }
    }

    /// Entries and steps in one order. Your messages the server hasn't placed yet come last.
    private static func merged(_ conversation: Conversation) -> [Piece] {
        let placed = conversation.entries.filter { $0.position != nil }
        let waiting = conversation.entries.filter { $0.position == nil }
        var pieces: [Piece] = []
        var steps = conversation.steps[...]
        for entry in placed {
            while let step = steps.first, step.position < entry.position ?? .max {
                pieces.append(.step(step))
                steps = steps.dropFirst()
            }
            pieces.append(.entry(entry))
        }
        pieces += steps.map(Piece.step)
        pieces += waiting.map(Piece.entry)
        return pieces
    }
}

/// What Ari did between two of its messages, in one turn: runs of steps, and its short notes.
public struct Trail: Equatable, Sendable, Identifiable {
    public let turn: TurnID
    public private(set) var parts: [Part] = []

    public var id: String { "trail " + (parts.first?.id ?? turn.rawValue) }

    public enum Part: Equatable, Sendable, Identifiable {
        case note(Conversation.Entry)
        case steps(StepRun)

        public var id: String {
            switch self {
            case .note(let entry): entry.id.rawValue
            case .steps(let run): run.id
            }
        }
    }

    enum Added {
        case note(Conversation.Entry)
        case step(Step)
    }

    init(turn: TurnID) {
        self.turn = turn
    }

    mutating func add(_ part: Added, live: Bool) {
        switch part {
        case .note(let entry):
            parts.append(.note(entry))
        case .step(let step):
            if case .steps(var run) = parts.last {
                run.add(step, live: live)
                parts[parts.count - 1] = .steps(run)
            } else {
                parts.append(.steps(StepRun(step, live: live)))
            }
        }
    }

    func folding(live: Bool) -> Trail {
        var trail = self
        trail.parts = parts.map { part in
            guard case .steps(var run) = part else { return part }
            run.isFolded = !live && run.stepCount > 1
            return .steps(run)
        }
        return trail
    }
}

/// Steps one after another, with no note between them. Similar steps in a row share a line ("Read 3
/// files"). Once the turn is over, a run of more than one step folds into a single line.
public struct StepRun: Equatable, Sendable, Identifiable {
    public private(set) var lines: [StepLine]
    /// Whether it shows as its summary alone, until you open it.
    public internal(set) var isFolded = false

    public var id: String { lines[0].id }
    public var stepCount: Int { lines.reduce(0) { $0 + $1.steps.count } }

    init(_ step: Step, live: Bool) {
        lines = [StepLine([step], live: live)]
    }

    mutating func add(_ step: Step, live: Bool) {
        let last = lines[lines.count - 1]
        if let group = StepLine.group(of: step), group == StepLine.group(of: last.steps[0]) {
            lines[lines.count - 1] = StepLine(last.steps + [step], live: live)
        } else {
            lines.append(StepLine([step], live: live))
        }
    }

    /// The folded line: what Ari did, briefly and in order ("Thought it through, searched the web,
    /// read 3 files").
    public var summary: String {
        var phrases: [String] = []
        for phrase in lines.map(\.phrase) where !phrases.contains(phrase) { phrases.append(phrase) }
        var text = phrases.prefix(3).joined(separator: ", ")
        if phrases.count > 3 { text += " and \(phrases.count - 3) more" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// One line of the trail: a step, or similar steps in a row.
public struct StepLine: Equatable, Sendable, Identifiable {
    /// One step, or several of the same sort.
    public let steps: [Step]
    /// Still running, in a turn that's still going.
    public let isRunning: Bool

    public var id: String { steps[0].id.rawValue }

    init(_ steps: [Step], live: Bool) {
        self.steps = steps
        isRunning = live && steps.contains { $0.outcome == nil }
    }

    /// What it says: the server's title, the heading Ari gave its thinking, or for similar steps in
    /// a row, a count ("Reading 3 files").
    public var title: String {
        if steps.count > 1, let group = Self.group(of: steps[0]) {
            return group.title(count: count(of: group), running: isRunning)
        }
        let step = steps[0]
        if step.kind == .thinking, let heading = step.heading, !heading.isEmpty { return heading }
        return step.title
    }

    /// While it runs, the one line of specifics under the title: the command, the page, the files.
    public var specifics: String? {
        guard isRunning, let step = steps.last(where: { $0.outcome == nil }) else { return nil }
        switch step.kind {
        case .command: return step.command
        case .webSearch: return step.url
        case .fileChange: return step.files?.map(\.path).joined(separator: ", ")
        case .tool:
            return [step.capability, step.operation].compactMap { $0 }.joined(separator: " · ")
        case .imageView: return step.path
        default: return nil
        }
    }

    /// How it ended, when that wasn't as planned.
    public var mark: String? {
        switch steps.last?.outcome {
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        case .failed: "Didn't finish"
        default: nil
        }
    }

    /// The line in a folded summary, in the past tense, starting lowercase.
    var phrase: String {
        let step = steps[0]
        if steps.count > 1, let group = Self.group(of: step) {
            return Self.lowercasingFirst(group.title(count: count(of: group), running: false))
        }
        switch step.kind {
        case .thinking: return "thought it through"
        case .webSearch: return "searched the web"
        default: return Self.lowercasingFirst(step.title)
        }
    }

    private func count(of group: Group) -> Int {
        let paths: [String] =
            switch group {
            case .read, .list: steps.flatMap { $0.actions ?? [] }.compactMap(\.path)
            case .edit: steps.flatMap { $0.files ?? [] }.map(\.path)
            case .search, .web: []
            }
        let distinct = Set(paths).count
        return distinct > 0 ? distinct : steps.count
    }

    private static func lowercasingFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    /// Sorts of step that share a line when they come one after another.
    enum Group: Equatable {
        case read, search, list, web, edit

        func title(count: Int, running: Bool) -> String {
            switch (self, running) {
            case (.read, true): "Reading \(count) files"
            case (.read, false): "Read \(count) files"
            case (.search, true): "Searching files"
            case (.search, false): "Searched files \(count) times"
            case (.list, true): "Looking in \(count) folders"
            case (.list, false): "Looked in \(count) folders"
            case (.web, true): "Searching the web"
            case (.web, false): "Searched the web \(count) times"
            case (.edit, true): "Editing \(count) files"
            case (.edit, false): "Edited \(count) files"
            }
        }
    }

    static func group(of step: Step) -> Group? {
        switch step.kind {
        case .webSearch: return .web
        case .fileChange: return .edit
        case .command:
            let types = Set((step.actions ?? []).map(\.type))
            guard types.count == 1 else { return nil }
            switch types.first {
            case .read: return .read
            case .search: return .search
            case .list: return .list
            default: return nil
            }
        default: return nil
        }
    }
}
