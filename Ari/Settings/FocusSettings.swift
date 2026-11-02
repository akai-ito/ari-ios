import AriKit
import SwiftUI

/// Your Focus, in Settings › Kumo: what the box last heard, and how to let Ito know your Focus.
struct FocusRow: View {
    let model: AppModel

    var body: some View {
        LabeledContent("Your Focus", value: told)
            .foregroundStyle(.ariText)
    }

    static func footer(_ lead: String) -> String {
        "Add Ito to a Focus and \(lead) hears when it's on: Sleep ends the night's check-ins, and "
            + "the others shape its lines. In the Settings app, open Focus, choose one, then Add "
            + "Filter › Ito, and say what it's for."
    }

    /// "Sleep, since 23:40", "No Focus since 07:10", or "Nothing yet".
    private var told: String {
        guard let told = model.focusTold else { return "Nothing yet" }
        let when = told.at.formatted(date: .omitted, time: .shortened)
        guard let focus = told.focus else { return "No Focus since \(when)" }
        let name = FocusUse(rawValue: focus.rawValue).flatMap {
            FocusUse.caseDisplayRepresentations[$0].map { String(localized: $0.title) }
        }
        return "\(name ?? focus.rawValue), since \(when)"
    }
}
