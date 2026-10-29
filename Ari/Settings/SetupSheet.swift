import AriKit
import SwiftUI

/// Setting up a capability: a sheet drawn from the fields it declares, with *Test connection*. A
/// password goes to your server once and never comes back; left empty, the saved one stays. A field
/// the provider can fill is connected instead: you approve a code on its page, where you're
/// already signed in, and the value goes to your server without passing through the phone.
struct SetupSheet: View {
    let capabilities: Capabilities
    let capability: Capability

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: SetupValue] = [:]
    @State private var checking = false
    @State private var check: CheckResult?
    @State private var saving = false
    @State private var problem: String?
    /// The code to approve, while connecting through the provider.
    @State private var connection: CapabilityConnection?
    @Environment(\.openURL) private var openURL

    /// The capability as the server last said, so a connected field shows as set.
    private var current: Capability { capabilities.capability(capability.id) ?? capability }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(current.fields) { field in
                        input(field)
                    }
                } footer: {
                    Text(footer)
                }
                .listRowBackground(Color.ariSurface)

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test connection").foregroundStyle(.ariText)
                            Spacer()
                            if checking {
                                ProgressView()
                            } else if let check {
                                Image(systemName: check.ok ? "checkmark" : "exclamationmark.circle")
                                    .font(.footnote.weight(.semibold))
                                Text(check.ok ? "It works" : "Didn't work")
                            }
                        }
                        .foregroundStyle(.ariSecondary)
                    }
                    .disabled(checking || !isComplete)
                } footer: {
                    // What went wrong, in full: a row cut it off.
                    if let problem {
                        Text(problem)
                    } else if let reason = check?.problem {
                        Text(reason)
                    } else if !capability.hosts.isEmpty {
                        Text("Reaches \(capability.hosts.joined(separator: ", ")).")
                    }
                }
                .listRowBackground(Color.ariSurface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle(capability.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(capability.state == .off ? "Turn on" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving || !isComplete)
                }
            }
            .onAppear(perform: fill)
        }
        .tint(.ariText)
    }

    @ViewBuilder
    private func input(_ field: SetupField) -> some View {
        if let connect = field.connect, connect.kind == .oauthDevice {
            connectRow(field, connect)
        } else {
            if let connect = field.connect, connect.kind == .link, let url = connect.url {
                Link(destination: url) {
                    Label(connect.title, systemImage: "arrow.up.forward.app")
                }
            }
            typed(field)
        }
    }

    /// Connecting through the provider: the code, copied, and its page, opened; then it waits for
    /// your server to have the value.
    @ViewBuilder
    private func connectRow(_ field: SetupField, _ connect: SetupField.Connect) -> some View {
        if field.set, connection == nil {
            HStack {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.ariText)
                Spacer()
                Button("Reconnect") { Task { await startConnecting() } }
                    .foregroundStyle(.ariSecondary)
            }
        } else if let connection {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter this code on the page that opened:")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
                Text(connection.code)
                    .font(.title2.monospaced().weight(.semibold))
                    .foregroundStyle(.ariText)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Button("Open the page again") { openURL(connection.url) }
                    Spacer()
                    ProgressView()
                }
                .font(.footnote)
            }
            .padding(.vertical, 4)
            .task(id: connection.code) { await waitForConnection(field.name, until: connection) }
        } else {
            Button {
                Task { await startConnecting() }
            } label: {
                Label(connect.title, systemImage: "link")
                    .font(.body.weight(.semibold))
            }
        }
    }

    private func startConnecting() async {
        problem = nil
        do {
            let started = try await capabilities.connect(capability.id)
            UIPasteboard.general.string = started.code
            connection = started
            openURL(started.url)
        } catch {
            problem = "Couldn't start connecting: \(error.plainWords)"
        }
    }

    /// Asks your server every couple of seconds until the field is set, or the code expires.
    private func waitForConnection(_ name: String, until started: CapabilityConnection) async {
        while !Task.isCancelled, Date.now < started.expiresAt.date {
            try? await Task.sleep(for: .seconds(2))
            await capabilities.refresh()
            if current.fields.first(where: { $0.name == name })?.set == true {
                connection = nil
                return
            }
        }
        if !Task.isCancelled {
            connection = nil
            problem = "The code expired before it was approved. Connect again to get a new one."
        }
    }

    @ViewBuilder
    private func typed(_ field: SetupField) -> some View {
        switch field.kind {
        case .secret:
            SecureField(
                field.label, text: text(field.name),
                prompt: Text(field.set ? "Saved. Type to replace it." : field.label))
        case .toggle:
            Toggle(field.label, isOn: toggle(field.name))
        case .choice:
            Picker(field.label, selection: text(field.name)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        default:
            TextField(field.label, text: text(field.name))
                .textContentType(nil)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var footer: String {
        let help = capability.fields.compactMap(\.help)
        let connects = capability.fields.contains { $0.connect?.kind == .oauthDevice }
        let typed = capability.fields.contains {
            $0.kind == .secret && $0.connect?.kind != .oauthDevice
        }
        return
            (help
            + (connects
                ? [
                    "Connecting gives the key straight to your server; it never passes through here."
                ]
                : [])
            + (typed
                ? ["Passwords go to your server once and never come back to this device."] : []))
            .joined(separator: " ")
    }

    /// Every required field has something: typed now, or saved before for a password, or
    /// connected.
    private var isComplete: Bool {
        current.fields.allSatisfy { field in
            guard field.required else { return true }
            if field.connect?.kind == .oauthDevice { return field.set }
            switch values[field.name] {
            case .text(let text): return !text.isEmpty || (field.kind == .secret && field.set)
            case .toggle: return true
            case nil: return field.kind == .toggle || (field.kind == .secret && field.set)
            }
        }
    }

    /// Only what changed: an empty password means keep the saved one.
    private var changes: [String: SetupValue] {
        values.filter { name, value in
            guard let field = capability.fields.first(where: { $0.name == name }) else {
                return false
            }
            if field.kind == .secret, value == .text("") { return false }
            return value != field.value
        }
    }

    private func fill() {
        for field in capability.fields where field.kind != .secret {
            if let value = field.value {
                values[field.name] = value
            } else if field.kind == .toggle {
                values[field.name] = .toggle(false)
            } else if field.kind == .choice, let first = field.options.first {
                values[field.name] = .text(first.value)
            }
        }
    }

    private func testConnection() async {
        checking = true
        problem = nil
        defer { checking = false }
        do {
            check = try await capabilities.check(capability.id, values: changes)
        } catch {
            check = nil
            problem = "Couldn't test it: \(error.plainWords)"
        }
    }

    private func save() async {
        saving = true
        problem = nil
        defer { saving = false }
        do {
            let saved = try await capabilities.save(capability.id, values: changes)
            if saved.state == .off { try await capabilities.setOn(capability.id, true) }
            dismiss()
        } catch {
            problem = "Couldn't save: \(error.plainWords)"
        }
    }

    private func text(_ name: String) -> Binding<String> {
        Binding(
            get: { if case .text(let text) = values[name] { text } else { "" } },
            set: {
                values[name] = .text($0)
                check = nil
            })
    }

    private func toggle(_ name: String) -> Binding<Bool> {
        Binding(
            get: { if case .toggle(let on) = values[name] { on } else { false } },
            set: {
                values[name] = .toggle($0)
                check = nil
            })
    }
}
