import AriKit
import SwiftUI

/// Settings: the server Ari talks to, notifications, and the icon. Native grouped lists in Ari's
/// slate, with soft white rather than coloured controls.
struct SettingsView: View {
    let model: AppModel
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSwitch = false

    var body: some View {
        NavigationStack {
            Form {
                server
                notifications
                #if os(iOS)
                    Section("App icon") {
                        AppIconChooser()
                    }
                    .listRowBackground(Color.ariSurface)
                #endif
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle("Settings")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Connect to another server?", isPresented: $confirmingSwitch,
                titleVisibility: .visible
            ) {
                Button("Disconnect from \(model.server?.name ?? "this server")", role: .destructive)
                {
                    dismiss()
                    model.connectAgain()
                }
            } message: {
                Text("Ari forgets this server's token. Your conversation stays on the server.")
            }
        }
        .tint(.ariText)
    }

    private var server: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.server?.name ?? "Your server")
                        .font(.body.weight(.semibold))
                    Text(model.lastAddress)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.ariTertiary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(Self.describe(session.link))
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            }
            .padding(.vertical, 2)
            if let server = model.server {
                LabeledContent("Version", value: server.version)
                LabeledContent("Protocol", value: server.protocolVersion.description)
            }
            Button("Connect to another server…") { confirmingSwitch = true }
        } header: {
            Text("Server")
        } footer: {
            Text("Your token stays in this device's Keychain.")
        }
        .listRowBackground(Color.ariSurface)
    }

    @ViewBuilder
    private var notifications: some View {
        #if os(iOS)
            Section {
                Toggle(
                    "When I'm away",
                    isOn: Binding(
                        get: { model.notificationsOn },
                        set: { on in
                            if on {
                                Task {
                                    // Turned off in iOS Settings before: only iOS can turn it back on.
                                    if !(await model.turnOnNotifications()) { openSystemSettings() }
                                }
                            } else {
                                model.turnOffNotifications()
                            }
                        }))
                Button("Focus and sounds…", action: openSystemSettings)
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Ari tells you when it's done or needs you, and only while you're not looking. "
                        + "Questions are time-sensitive, so they can reach you during Focus; choose "
                        + "in iOS Settings.")
            }
            .listRowBackground(Color.ariSurface)
        #endif
    }

    #if os(iOS)
        private func openSystemSettings() {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    #endif

    private static func describe(_ link: Session.Link) -> String {
        switch link {
        case .live: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .offline: "No connection"
        case .paused: "Paused"
        }
    }
}
