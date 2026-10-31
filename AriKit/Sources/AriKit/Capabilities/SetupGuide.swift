import Foundation

/// A setup field's help, read as a short guide: an introduction, numbered steps, then notes.
///
/// A step is a line that starts with its number, a full stop (or a bracket) and a space: "1. Open
/// your Apple Account". Lines before the first step are the introduction. A line straight after a
/// step, with no blank line between, carries that step on; after a blank line, it's a note. Help
/// without numbered lines is all introduction. Blank lines separate paragraphs, and lines within a
/// paragraph join with a space.
///
///     Mail and Calendar from your iCloud account. Apple doesn't let other apps sign in, so it
///     takes an app password: about a minute.
///     1. Open your Apple Account
///     2. Sign-In and Security › App-Specific Passwords
///     3. Create one called "Ito", then copy it
///     4. Paste it here
public struct SetupGuide: Sendable, Equatable {
    /// Paragraphs before the steps.
    public let intro: [String]
    /// Each step's words, without its number.
    public let steps: [String]
    /// Paragraphs after the steps.
    public let notes: [String]

    public init(intro: [String] = [], steps: [String] = [], notes: [String] = []) {
        self.intro = intro
        self.steps = steps
        self.notes = notes
    }

    public init(help: String?) {
        var intro: [String] = []
        var steps: [String] = []
        var notes: [String] = []
        /// The paragraph being read, before the steps or after them.
        var paragraph: [String] = []
        /// Whether the last line was a step's, so the next one carries it on.
        var inStep = false

        func endParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
            if steps.isEmpty { intro.append(text) } else { notes.append(text) }
            paragraph = []
        }

        for raw in (help ?? "").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                endParagraph()
                inStep = false
            } else if let step = Self.step(line) {
                endParagraph()
                steps.append(step)
                inStep = true
            } else if inStep, let last = steps.popLast() {
                steps.append(last + " " + line)
            } else {
                paragraph.append(line)
            }
        }
        endParagraph()
        self.init(intro: intro, steps: steps, notes: notes)
    }

    /// A step's words, if the line starts with a number, then "." or ")", then a space.
    private static func step(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /(\d{1,2})[.)]\s+(.+)/) else { return nil }
        return String(match.output.2)
    }
}

extension Capability {
    /// The field the provider fills through its own sign-in, with a code you approve there.
    public var deviceField: SetupField? {
        fields.first { $0.connect?.kind == .oauthDevice }
    }

    /// The fields you fill in yourself: all but the one the provider fills.
    public var typedFields: [SetupField] {
        fields.filter { $0.connect?.kind != .oauthDevice }
    }

    /// The page where the provider makes a value to paste here, such as an app password.
    public var link: SetupField.Connect? {
        fields.lazy.compactMap(\.connect).first { $0.kind == .link && $0.url != nil }
    }

    /// The field whose help guides setup: the first you fill in whose help has numbered steps, or
    /// else the one with the link.
    public var guideField: SetupField? {
        typedFields.first { !SetupGuide(help: $0.help).steps.isEmpty }
            ?? typedFields.first { $0.connect?.kind == .link }
    }

    /// How setup is explained: the guide field's help, read as steps.
    public var setupGuide: SetupGuide { SetupGuide(help: guideField?.help) }
}
