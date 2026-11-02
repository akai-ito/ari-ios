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
        let client = model.client()
        _client = State(initialValue: client)
        _capabilities = State(initialValue: client.map(Capabilities.init(client:)))
        _models = State(initialValue: client.map(Models.init(client:)))
        _backup = State(initialValue: client.map { Backup(client: $0) })
    }

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSwitch = false
    /// For Kumo's settings, made once with Settings.
    @State private var client: ItoClient?
    /// Made with Settings, so a place already on the stack (from `ARI_SETTINGS`) has it at once.
    @State private var capabilities: Capabilities?
    @State private var models: Models?
    /// Where memory is backed up, and backing it up to GitHub.
    @State private var backup: Backup?
    /// Ari's voice on the server, from the main view.
    @Environment(Voices.self) private var voices: Voices?
    @State private var path = Self.startingPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    ServerProblems(problems: session.problems)
                    server
                    KumoSettings(model: model, client: client)
                    MorningSettings(model: model, client: client)
                    FocusSettings(model: model)
                    capabilitiesSection
                    GettingStartedAgain(session: session) { dismiss() }
                    MemoryBackupSection(
                        backup: backup, isBackedUp: model.server?.setup?.memoryBackup
                    )
                    .id(SettingsAnchor.memory)
                    notifications
                    TalkSettings()
                    Section("App icon") {
                        AppIconChooser()
                    }
                    .listRowBackground(Color.ariSurface)
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(.ariBackground)
                .task {
                    async let capabilitiesLoaded: Void? = capabilities?.refresh()
                    async let modelsLoaded: Void? = models?.refresh()
                    async let backupLoaded: Void? = backup?.refresh()
                    _ = await (capabilitiesLoaded, modelsLoaded, backupLoaded)
                    #if DEBUG
                        if let anchor = DebugScript.settingsAnchor {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    #endif
                }
                .navigationTitle("Settings")
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .capabilities:
                        if let capabilities { CapabilitiesView(capabilities: capabilities) }
                    case .capability(let id, let setup):
                        if let capabilities {
                            CapabilityView(capabilities: capabilities, id: id, opensSetup: setup)
                        }
                    case .model:
                        if let models {
                            ModelPickerView(models: models, chosen: model.refreshServer)
                        }
                    case .voice:
                        if let voices { VoicePickerView(voices: voices) }
                    case .memoryBackup:
                        if let backup { MemoryBackupPage(backup: backup) }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .confirmationDialog(
                    "Connect to another server?", isPresented: $confirmingSwitch,
                    titleVisibility: .visible
                ) {
                    Button(
                        "Disconnect from \(model.server?.name ?? "this server")", role: .destructive
                    ) {
                        dismiss()
                        model.connectAgain()
                    }
                } message: {
                    Text("Ito forgets this server's token. Your conversations stay on the server.")
                }
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
                if models != nil || server.agent.model != nil {
                    NavigationLink(value: SettingsRoute.model) {
                        LabeledContent("Model", value: modelSummary(server.agent))
                    }
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
                    "What \(LeadName.current) can know about and do. Passwords go to your server, never back to Ito."
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

    /// The model and how hard it thinks, as the picker names them once it has loaded: "GPT-6-Luna ·
    /// Balanced". Until then, what the server reports.
    private func modelSummary(_ agent: ServerInfo.Agent) -> String {
        guard let list = models?.list, let chosen = models?.chosenModel else {
            return agent.model ?? ""
        }
        let effort = chosen.choices(current: list.chosen.effort).first {
            $0.effort.id == list.chosen.effort
        }
        let word = effort.map { ModelPickerView.word($0.step, effort: $0.effort) }
        return [chosen.title, word].compactMap(\.self).joined(separator: " · ")
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
                    "\(LeadName.current) tells you when it's done or needs you, and only while you're not "
                        + "looking. Questions are time-sensitive, so they can reach you during "
                        + "Focus; choose in iOS Settings.")
            }
        }
        .listRowBackground(Color.ariSurface)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

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

/// How calls with Ari go: Ari's voice, from the server, and whether it knows yours.
private struct TalkSettings: View {
    @Environment(Voices.self) private var voices: Voices?
    @State private var confirmsRelearning = false
    @State private var problem: String?

    var body: some View {
        Section {
            NavigationLink(value: SettingsRoute.voice) {
                LabeledContent("Voice", value: voices?.chosen?.name ?? "")
            }
            .disabled(voices == nil)
            if let voices, let voiceprint = voices.voiceprint {
                LabeledContent(
                    "Your voice",
                    value: voiceprint == .learnt ? "\(LeadName.current) knows it" : "Learning")
                Button("Relearn my voice") { confirmsRelearning = true }
                    .disabled(voices.relearning)
                    .confirmationDialog(
                        "Relearn your voice?", isPresented: $confirmsRelearning,
                        titleVisibility: .visible
                    ) {
                        Button("Relearn") { relearn(voices) }
                    } message: {
                        Text(
                            "\(LeadName.current) forgets how you sound and learns again from the next couple of "
                                + "minutes you talk on a call. Until then, any voice can hold "
                                + "a turn open.")
                    }
            }
        } header: {
            Text("Talk")
        } footer: {
            if let problem {
                Text(problem)
            } else if let voices, !voices.canTalk, let reason = voices.reason {
                Text(reason)
            } else if voices?.voiceprint == .learning {
                Text(
                    "\(LeadName.current) learns your voice from your first couple of minutes on calls, so "
                        + "only you hold a turn open.")
            }
        }
        .listRowBackground(Color.ariSurface)
    }

    private func relearn(_ voices: Voices) {
        problem = nil
        Task {
            do throws(RequestError) {
                try await voices.relearn()
            } catch {
                problem = "Couldn't relearn your voice: \(error.plainWords)"
            }
        }
    }
}

/// Going through getting started again, to see it: nothing is wiped, connected accounts stay
/// connected, and Kumo reads mail again only for an account added now. Settings closes so getting
/// started can open over everything.
private struct GettingStartedAgain: View {
    let session: Session
    let close: () -> Void

    @State private var opening = false
    @State private var problem: String?

    var body: some View {
        Section {
            Button {
                Task { await open() }
            } label: {
                HStack {
                    Text("Go through getting started again")
                    Spacer()
                    if opening { ProgressView() }
                }
            }
            .disabled(opening)
        } footer: {
            Text(
                problem
                    ?? "Nothing is wiped. Connected accounts stay connected, and \(LeadName.current) reads mail again only for an account you add."
            )
        }
        .listRowBackground(Color.ariSurface)
    }

    private func open() async {
        opening = true
        problem = nil
        do throws(RequestError) {
            try await session.replayOnboarding()
            close()
        } catch {
            problem = "Couldn't open getting started: \(error.plainWords)"
        }
        opening = false
    }
}

/// What's wrong on the server, at the top of Settings until it's fixed: each problem, what it means
/// and how to fix it.
private struct ServerProblems: View {
    let problems: [ServerProblem]

    var body: some View {
        if !problems.isEmpty {
            Section {
                ForEach(problems) { problem in
                    ProblemDetail(problem: problem).padding(.vertical, 4)
                }
            } header: {
                Text("Needs you")
            } footer: {
                Text("Each goes away by itself once it's fixed.")
            }
            .listRowBackground(Color.ariSurface)
        }
    }
}
