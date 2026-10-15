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

    private var notifications: some View {
        Section {
            Toggle("When I'm away", isOn: .constant(false))
            Toggle("Questions get through Focus", isOn: .constant(false))
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                "Ari will tell you when it's done or needs you. This starts working once your "
                    + "server is updated to support it.")
        }
        .disabled(true)
        .listRowBackground(Color.ariSurface)
    }

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
