import AppIntents
import SwiftUI
import WidgetKit

/// Ari's controls, for Control Centre, the Lock Screen and the Action button.
@main
struct AriControls: WidgetBundle {
    var body: some Widget {
        TalkControl()
    }
}

/// One press and Ari opens on a call: set as the Action button, a walk starts from your pocket.
struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Talk") {
            ControlWidgetButton(action: CallAriIntent()) {
                Label("Talk to Kumo", systemImage: "waveform")
            }
        }
        .displayName("Talk to Kumo")
        .description("Start a call with Kumo, to talk hands-free.")
    }
}
