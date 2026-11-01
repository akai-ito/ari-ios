import AppIntents
import AriKit

/// What a Focus is for, as you say when you add Ito to it.
enum FocusUse: String, AppEnum {
    case sleep, work, fitness, personal, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Focus"
    static let caseDisplayRepresentations: [FocusUse: DisplayRepresentation] = [
        .sleep: "Sleep", .work: "Work", .fitness: "Fitness", .personal: "Personal",
        .other: "Something else",
    ]
}

/// Ito's Focus filter. Add Ito to a Focus in Settings › Focus and say what it's for; then iOS
/// tells Ari each time that Focus turns on or off, and Ari tells your box, so Kumo knows you're
/// asleep, working or out. Off comes with nothing chosen.
struct ItoFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Let Ito know"
    static let description = IntentDescription(
        "Tells Kumo when this Focus is on, so its lines and check-ins fit what you're doing. A Sleep Focus ends the night's check-ins."
    )

    @Parameter(title: "This Focus is for")
    var use: FocusUse?

    @Dependency private var model: AppModel

    var displayRepresentation: DisplayRepresentation {
        guard let use else {
            return DisplayRepresentation(
                title: "Let Ito know", subtitle: "Choose what this Focus is for")
        }
        return DisplayRepresentation(
            title: "Let Ito know",
            subtitle: "\(FocusUse.caseDisplayRepresentations[use]?.title ?? "This Focus") is on")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await model.tellFocus(use.map { FocusKind(rawValue: $0.rawValue) })
        return .result()
    }
}
