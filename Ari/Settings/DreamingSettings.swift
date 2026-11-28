import AriKit
import SwiftUI

/// Settings › Dreaming: when Kumo dreams each night, and when it last did. Dream now and what the
/// dream did live on the Desk, under the moon.
struct DreamingSettings: View {
    let client: ItoClient?

    @State private var schedule: DreamSchedule?
    /// The time in the picker, ahead of the box while a change is on its way.
    @State private var chosen: DreamSchedule.Time?
    @State private var problem: Problem?

    private enum Problem: Equatable {
        /// The box doesn't dream: it runs an Ito from before the dream.
        case unsupported
        case unreachable(String)
        case notSaved(String)
    }

    var body: some View {
        let name = LeadName.current
        Section {
            DatePicker(
                "Dream at",
                selection: Binding(
                    get: { (chosen ?? schedule?.time ?? .standard).date() },
                    set: { chosen = DreamSchedule.Time($0) }),
                displayedComponents: .hourAndMinute
            )
            .disabled(schedule == nil)
            LabeledContent("Last dream", value: lastDream)
        } header: {
            Text("Dreaming")
        } footer: {
            Text(footer(name: name))
        }
        .listRowBackground(Color.ariSurface)
        .task { await load() }
        // The picker moves through times as you turn it: only where it settles goes to the box.
        .task(id: chosen) {
            guard let chosen, chosen != schedule?.time else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await save(chosen)
        }
    }

    private var lastDream: String {
        if schedule?.dreaming != nil { return "Dreaming now" }
        if let latest = schedule?.latest { return latest.summary() }
        return schedule == nil ? "" : "Not yet"
    }

    private func footer(name: String) -> String {
        switch problem {
        case .unsupported:
            return
                "Your box doesn't dream yet. Update Ito on it, and \(name) dreams over each day at night."
        case .unreachable(let words): return "Couldn't read when \(name) dreams: \(words)"
        case .notSaved(let words): return "Couldn't change the time: \(words)"
        case nil:
            return
                "Each night \(name) reads your day, tidies its memory, sets tomorrow up and writes your journal. What it did waits under the moon on your Desk, with Dream now."
        }
    }

    private func load() async {
        guard let client else { return }
        do throws(RequestError) {
            schedule = try await client.dreamSchedule()
            problem = nil
        } catch {
            problem = error.status == 404 ? .unsupported : .unreachable(error.plainWords)
        }
    }

    private func save(_ time: DreamSchedule.Time) async {
        guard let client else { return }
        do throws(RequestError) {
            schedule = try await client.changeDreamTime(to: time)
            problem = nil
        } catch {
            problem = .notSaved(error.plainWords)
        }
        // The picker shows what the box keeps.
        if chosen == time { chosen = nil }
    }
}
