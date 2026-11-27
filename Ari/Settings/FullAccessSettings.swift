import AriKit
import LocalAuthentication
import SwiftUI

/// Settings › Full access: Kumo out of its sandbox, from its next message. Turning it on asks for
/// Face ID, or the passcode, first; turning it off asks nothing. The switch follows the server, so
/// a change from another device shows here too, and the main chat shows a marker while it's on.
struct FullAccessSettings: View {
    let session: Session

    /// Where the switch is while a change is on its way: it flips at once, and the lock with it,
    /// while Face ID asks and the box answers.
    @State private var pending: Bool?
    /// Whether the box knows full access at all: it runs an Ito from before it, when it doesn't.
    @State private var supported = true
    @State private var problem: String?

    var body: some View {
        let isOn = pending ?? session.access.isFull
        let canCheck = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        Section {
            Toggle(
                isOn: Binding(
                    get: { isOn },
                    set: { on in Task { await change(to: on) } })
            ) {
                HStack(spacing: 10) {
                    Image(systemName: isOn ? "lock.open" : "lock")
                        .foregroundStyle(.ariSecondary)
                        .frame(width: 20)
                        .contentTransition(.symbolEffect(.replace))
                    Text("Full access")
                }
            }
            // Turning it on needs a way to check it's you; turning it off never does.
            .disabled(pending != nil || !supported || (!isOn && !canCheck))
        } header: {
            Text("Full access")
        } footer: {
            Text(problem ?? footer(isOn: isOn, canCheck: canCheck))
        }
        .listRowBackground(Color.ariSurface)
        .task {
            do throws(RequestError) {
                try await session.refreshAccess()
            } catch {
                // The snapshot already says how Kumo runs; only an older box changes the switch.
                supported = error.status != 404
            }
        }
    }

    private func footer(isOn: Bool, canCheck: Bool) -> String {
        let name = LeadName.current
        guard supported else {
            return "Your box doesn't offer full access yet. Update Ito on it, and this turns on."
        }
        let since = session.access.since.map { "On since \(DayLabel.describe($0.date)). " } ?? ""
        let what =
            "\(name) works inside a sandbox: its own folder and the tools you've connected. With full access it can use the whole box, any file and any program, from its next message; the dream follows it too."
        if isOn { return since + what }
        return canCheck
            ? what + " Turning it on asks for Face ID."
            : what + " It needs a passcode on this iPhone, so only you can turn it on."
    }

    private func change(to on: Bool) async {
        guard pending == nil else { return }
        problem = nil
        pending = on
        defer { pending = nil }
        do throws(RequestError) {
            if on {
                guard await confirmed() else { return }
                try await session.giveFullAccess()
            } else {
                try await session.endFullAccess()
            }
        } catch {
            problem =
                on
                ? "Couldn't turn on full access: \(error.plainWords)"
                : "Couldn't turn off full access: \(error.plainWords)"
        }
    }

    /// Face ID, or the passcode, says it's you. Cancelling is a quiet no.
    private func confirmed() async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Give \(LeadName.current) full access to your box")
        } catch let error as LAError
            where [.userCancel, .appCancel, .systemCancel].contains(error.code)
        {
            return false
        } catch {
            problem = "That wasn't confirmed, so \(LeadName.current) stays in its sandbox."
            return false
        }
    }
}
