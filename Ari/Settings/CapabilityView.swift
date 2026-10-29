import AriKit
import SwiftUI

/// One capability's page: what it is, On, why it needs you, its setup, and what it reaches.
struct CapabilityView: View {
    let capabilities: Capabilities
    let id: CapabilityID
    var opensSetup = false

    @State private var settingUp = false
    @State private var problem: String?

    var body: some View {
        Form {
            if let capability = capabilities.capability(id) {
                content(capability)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle(capabilities.capability(id)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // Opened straight here, nothing has loaded the list yet.
        .task { if capabilities.capability(id) == nil { await capabilities.refresh() } }
        .onAppear { if opensSetup { settingUp = true } }
        .sheet(isPresented: $settingUp) {
            if let capability = capabilities.capability(id) {
                SetupSheet(capabilities: capabilities, capability: capability)
            }
        }
    }

    @ViewBuilder
    private func content(_ capability: Capability) -> some View {
        Section {
            Text(capability.summary)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.ariText)
                .lineSpacing(3)
                .padding(.vertical, 4)
            Toggle("On", isOn: switchBinding(capability))
                .disabled(capabilities.switching.contains(id))
        } footer: {
            if let problem {
                Text(problem)
            } else if capability.state == .needsYou, let detail = capability.detail {
                Text("Needs you: \(detail)")
            } else if capability.state == .setup {
                Text("It's on, but setup isn't finished, so Ari can't use it yet.")
            }
        }
        .listRowBackground(Color.ariSurface)

        if !capability.fields.isEmpty {
            Section {
                ForEach(capability.fields) { field in
                    LabeledContent(field.label, value: Self.describe(field))
                }
                Button(Self.setupTitle(capability)) { settingUp = true }
            } header: {
                Text("Setup")
            }
            .listRowBackground(Color.ariSurface)
        }

        if !capability.hosts.isEmpty || !capability.folders.isEmpty {
            Section {
                ForEach(capability.hosts, id: \.self) { host in
                    Text(host).font(.footnote.monospaced()).foregroundStyle(.ariSecondary)
                }
                ForEach(capability.folders, id: \.self) { folder in
                    Text(folder).font(.footnote.monospaced()).foregroundStyle(.ariSecondary)
                }
            } header: {
                Text("Reaches")
            } footer: {
                Text(
                    "Switching \(capability.title) off keeps what it has, so it picks up where it left off."
                )
            }
            .listRowBackground(Color.ariSurface)
        }
    }

    private func switchBinding(_ capability: Capability) -> Binding<Bool> {
        Binding(
            get: { capability.state != .off },
            set: { on in
                problem = nil
                Task {
                    do throws(RequestError) {
                        try await capabilities.setOn(id, on)
                        // On, but setup isn't complete: the sheet asks for what's missing.
                        if on, capabilities.capability(id)?.state == .setup { settingUp = true }
                    } catch {
                        problem = "Couldn't switch it \(on ? "on" : "off"): \(error.plainWords)"
                    }
                }
            })
    }

    /// A field's saved value as a row shows it. Passwords show only whether one is saved.
    /// What opens setup: Reconnect when a connection lapsed, the provider's own words before it's
    /// connected, otherwise setting it up or changing it.
    static func setupTitle(_ capability: Capability) -> String {
        let connect = capability.fields.first { $0.connect?.kind == .oauthDevice }?.connect
        if let connect {
            if capability.state == .needsYou { return "Reconnect…" }
            if !capability.isSetUp { return connect.title + "…" }
        }
        return capability.isSetUp ? "Change setup…" : "Set up…"
    }

    static func describe(_ field: SetupField) -> String {
        if field.connect?.kind == .oauthDevice { return field.set ? "Connected" : "Not connected" }
        return switch (field.kind, field.value) {
        case (.secret, _): field.set ? "Saved" : "Not set"
        case (_, .toggle(let on)?): on ? "On" : "Off"
        case (.choice, .text(let value)?):
            field.options.first { $0.value == value }?.label ?? value
        case (_, .text(let text)?) where !text.isEmpty: text
        default: "Not set"
        }
    }
}
