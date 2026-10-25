import AriKit
import SwiftUI

/// Settings: the server Ari talks to, notifications, and the icon. Native grouped lists in Ari's
/// slate, with soft white rather than coloured controls.
struct SettingsView: View {
    let model: AppModel
    let session: Session

    init(model: AppModel, session: Session) {
        self.model = model
        self.session = session
        _capabilities = State(initialValue: model.client().map(Capabilities.init(client:)))
    }

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSwitch = false
    /// Made with Settings, so a place already on the stack (from `ARI_SETTINGS`) has it at once.
    @State private var capabilities: Capabilities?
    @State private var path = Self.startingPath

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                server
                capabilitiesSection
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
            .task { await capabilities?.refresh() }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                if let capabilities {
                    switch route {
                    case .capabilities: CapabilitiesView(capabilities: capabilities)
                    case .capability(let id, let setup):
                        CapabilityView(capabilities: capabilities, id: id, opensSetup: setup)
                    }
                }
            }
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                    // The Mac's Settings window closes like any other.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                #endif
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
                if let engine = server.agent.model {
                    LabeledContent("Model", value: engine)
                }
                if let account = server.agent.account {
                    LabeledContent("Signed in with", value: Self.describe(account))
                }
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
    private var capabilitiesSection: some View {
        if let capabilities {
            Section {
                NavigationLink(value: SettingsRoute.capabilities) {
                    LabeledContent("Capabilities", value: Self.summary(of: capabilities))
                }
            } footer: {
                Text(
                    "What Ari can know about and do. Passwords go to your server, never back to Ari."
                )
            }
            .listRowBackground(Color.ariSurface)
        }
    }

    /// Where Settings opens: at the top, or, in debug builds, wherever `ARI_SETTINGS` says
    /// (`capabilities`, `capability:<id>` or `setup:<id>`).
    private static var startingPath: [SettingsRoute] {
        #if DEBUG
            DebugScript.settingsPath
        #else
            []
        #endif
    }

    /// "2 on", or the one that needs you.
    private static func summary(of capabilities: Capabilities) -> String {
        if let needy = capabilities.all.first(where: { $0.state == .needsYou }) {
            return "\(needy.title) needs you"
        }
        let on = capabilities.all.filter { $0.state == .on }.count
        return capabilities.all.isEmpty ? "" : "\(on) on"
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
                if model.notificationsOn, let problem = model.notificationProblem {
                    Text("Notifications couldn't start on this iPhone: \(problem)")
                } else if model.server?.setup?.notifications == false {
                    Text(
                        "Your server can't send notifications yet. Run ito push setup on it, and "
                            + "they start.")
                } else {
                    Text(
                        "Ari tells you when it's done or needs you, and only while you're not "
                            + "looking. Questions are time-sensitive, so they can reach you during "
                            + "Focus; choose in iOS Settings.")
                }
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

    /// How the agent is signed in, in a few words: "ChatGPT Plus · example.com".
    private static func describe(_ account: ServerInfo.Agent.Account) -> String {
        let kind =
            switch account.kind {
            case "chatgpt":
                ["ChatGPT", account.plan?.capitalized].compactMap(\.self).joined(separator: " ")
            case "api_key": "An API key"
            default: "Another account"
            }
        return [kind, account.emailDomain].compactMap(\.self).joined(separator: " · ")
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
