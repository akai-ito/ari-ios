import AriKit
import SwiftUI

/// Settings › Dreaming: when Kumo dreams each night, and when it last did. Dream now and what the
/// dream did live on the Desk, under the moon.
struct DreamingSettings: View {
    /// The Desk's dream, which Settings shares: one model for the moon page and these rows.
    @Environment(Dreams.self) private var dreams: Dreams?

    /// The time in the picker, ahead of the box while a change is on its way.
    @State private var chosen: DreamTimeOfDay?
    @State private var notSaved: String?

    var body: some View {
        let name = LeadName.current
        Section {
            DatePicker(
                "Dream at",
                selection: Binding(
                    get: { (chosen ?? kept ?? .standard).date() },
                    set: { chosen = DreamTimeOfDay($0) }),
                displayedComponents: .hourAndMinute
            )
            .disabled(dreams?.state == nil)
            LabeledContent("Last dream", value: lastDream)
        } header: {
            Text("Dreaming")
        } footer: {
            Text(footer(name: name))
        }
        .listRowBackground(Color.ariSurface)
        .task {
            // Ask again if the Desk's first read failed, such as before the box was reachable.
            if dreams?.state == nil { await dreams?.refresh() }
        }
        // The picker moves through times as you turn it: only where it settles goes to the box.
        .task(id: chosen) {
            guard let chosen, chosen != kept else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await save(chosen)
        }
    }

    /// The time the box keeps.
    private var kept: DreamTimeOfDay? { dreams?.state.flatMap { DreamTimeOfDay($0.time) } }

    private var lastDream: String {
        guard let state = dreams?.state else { return "" }
        if state.dreaming != nil { return "Dreaming now" }
        return state.latest?.summary() ?? "Not yet"
    }

    private func footer(name: String) -> String {
        if let notSaved { return "Couldn't change the time: \(notSaved)" }
        switch dreams?.load {
        case .failed(let error) where error.status == 404:
            // The box runs an Ito from before the dream.
            return
                "Your box doesn't dream yet. Update Ito on it, and \(name) dreams over each day at night."
        case .failed(let error) where dreams?.state == nil:
            return "Couldn't read when \(name) dreams: \(error.plainWords)"
        default:
            return
                "Each night \(name) reads your day, tidies its memory, sets tomorrow up and writes your journal. What it did waits under the moon on your Desk, with Dream now."
        }
    }

    private func save(_ time: DreamTimeOfDay) async {
        guard let dreams else { return }
        do throws(RequestError) {
            try await dreams.setTime(time.description)
            notSaved = nil
        } catch {
            notSaved = error.plainWords
        }
        // The picker shows what the box keeps.
        if chosen == time { chosen = nil }
    }
}
