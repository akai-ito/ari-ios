import AriKit
import SwiftUI

/// Setting up a capability, drawn from the fields it declares. A short introduction; numbered steps
/// when a field's help gives them, with the page that makes a password as a button in the first;
/// the fields to fill in, together; *Test connection* and what it found. A password goes to your
/// box once and never comes back; left empty, the saved one stays. A field the provider can fill is
/// connected instead: you enter a code on its page, where you sign in, and the value goes to your
/// box without passing through the phone.
struct SetupSheet: View {
    let capabilities: Capabilities
    let capability: Capability

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var values: [String: SetupValue] = [:]
    @State private var checking = false
    @State private var check: CheckResult?
    @State private var saving = false
    @State private var problem: String?
    /// The code to enter, while connecting through the provider.
    @State private var connection: CapabilityConnection?
    /// Asking the box for a code.
    @State private var starting = false
    @ScaledMetric(relativeTo: .footnote) private var stepSize: CGFloat = 24
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 38

    /// The capability as the server last said, so a connected field shows as set.
    private var current: Capability { capabilities.capability(capability.id) ?? capability }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(intro.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundStyle(.ariSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let field = current.deviceField, let connect = field.connect {
                        device(field, connect)
                    }
                    steps
                    if !current.typedFields.isEmpty {
                        inputs
                        HStack(spacing: 12) {
                            Button("Test connection") { Task { await testConnection() } }
                                .buttonStyle(SetupPill())
                                .disabled(checking || !isComplete)
                            if checking { ProgressView() }
                        }
                    }
                    outcome
                    ForEach(Array(footnotes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .task {
                // Not connected yet: the code is ready, and copied, by the time you look.
                if let field = current.deviceField, !field.set, connection == nil {
                    await startConnecting()
                }
            }
        }
        .tint(.ariText)
    }

    // MARK: - The parts

    /// The guide's introduction; the sign-in's, while a code is wanted; or the capability's summary.
    private var intro: [String] {
        let guide = current.setupGuide
        if !guide.intro.isEmpty { return guide.intro }
        if let field = current.deviceField, connection != nil || starting || !field.set {
            return ["Sign in on the page that opens, then enter this code."]
        }
        return current.summary.isEmpty ? [] : [current.summary]
    }

    /// The guide's numbered steps, the link in the first; or the link alone.
    @ViewBuilder
    private var steps: some View {
        let guide = current.setupGuide
        let link = current.link
        if !guide.steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                    step(index + 1, text, link: index == 0 ? link : nil)
                }
            }
        } else if let link, let url = link.url {
            Link(link.title, destination: url).buttonStyle(SetupPill())
        }
    }

    private func step(_ number: Int, _ text: String, link: SetupField.Connect?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.ariBackground)
                .frame(width: stepSize, height: stepSize)
                .background(.ariBone, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.ariText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityLabel("Step \(number): \(text)")
                if let link, let url = link.url {
                    Link(link.title, destination: url).buttonStyle(SetupPill())
                }
            }
        }
    }

    /// The fields to fill in, together: the label on the left, the value beside it.
    private var inputs: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(Array(current.typedFields.enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider().overlay(Color.ariLine) }
                GridRow {
                    Text(field.label)
                        .font(.subheadline)
                        .foregroundStyle(.ariSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: 150, minHeight: 50, alignment: .leading)
                    input(field)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(.ariSurface, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.ariLine.opacity(0.7)))
    }

    @ViewBuilder
    private func input(_ field: SetupField) -> some View {
        let placeholder = field.required ? "Required" : "Optional"
        switch field.kind {
        case .secret:
            // Saved before: bullets, as if filled. Typing replaces it.
            SecureField(
                field.label, text: text(field.name),
                prompt: field.set
                    ? Text("••••••••••••").foregroundStyle(.ariText)
                    : Text(placeholder).foregroundStyle(.ariTertiary)
            )
            .font(.subheadline.monospaced())
            .foregroundStyle(.ariText)
        case .toggle:
            Toggle(field.label, isOn: toggle(field.name))
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .choice:
            Picker(field.label, selection: text(field.name)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        default:
            TextField(
                field.label, text: text(field.name),
                prompt: Text(placeholder).foregroundStyle(.ariTertiary)
            )
            .font(.subheadline.monospaced())
            .foregroundStyle(.ariText)
            .textContentType(nil)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    /// Connecting through the provider: the code, copied, and a button to its page; then it waits
    /// for your box to have the value.
    private func device(_ field: SetupField, _ connect: SetupField.Connect) -> some View {
        VStack(spacing: 22) {
            if let connection {
                code(connection.code)
                Button(connect.title) { openURL(connection.url) }
                    .buttonStyle(SetupPill(primary: true))
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for you to sign in…")
                        .font(.footnote)
                        .foregroundStyle(.ariSecondary)
                }
            } else if field.set, !starting {
                HStack {
                    line("Connected", ok: true)
                    Spacer()
                    Button("Reconnect") { Task { await startConnecting() } }
                        .buttonStyle(SetupPill())
                }
            } else {
                code(nil)
                if problem != nil, !starting {
                    Button("Try again") { Task { await startConnecting() } }
                        .buttonStyle(SetupPill(primary: true))
                }
            }
            if let help = field.help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: connection?.code) {
            if let connection { await waitForConnection(field.name, until: connection) }
        }
    }

    /// The code to enter, large, in a card; a spinner until there is one.
    private func code(_ code: String?) -> some View {
        VStack(spacing: 12) {
            if let code {
                Text(code)
                    .font(.system(size: codeSize, weight: .semibold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .speechSpellsOutCharacters()
                    .textSelection(.enabled)
                Label("Copied", systemImage: "doc.on.doc")
                    .font(.footnote)
                    .foregroundStyle(.ariTertiary)
            } else {
                ProgressView().frame(minHeight: codeSize * 1.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .background(.ariSurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.ariLine.opacity(0.7)))
    }

    /// What went wrong, or what *Test connection* found.
    @ViewBuilder
    private var outcome: some View {
        if let problem {
            line(problem, ok: false)
        } else if let check {
            line(check.problem ?? check.summary ?? "It works", ok: check.ok)
        }
    }

    private func line(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? Color.ariBone : .ariSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.ariText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The guide's notes, the other fields' help, and where a password goes.
    private var footnotes: [String] {
        let guide = current.guideField?.name
        let help = current.typedFields.filter { $0.name != guide }.compactMap(\.help)
        let password =
            current.typedFields.contains { $0.kind == .secret }
            ? [
                "The password goes to your box only, and is never shown again here or sent to any app."
            ]
            : []
        return current.setupGuide.notes + help + password
    }

    // MARK: - Connecting

    private func startConnecting() async {
        problem = nil
        starting = true
        defer { starting = false }
        do {
            let started = try await capabilities.connect(capability.id)
            UIPasteboard.general.string = started.code
            connection = started
        } catch {
            problem = "Couldn't start connecting: \(error.plainWords)"
        }
    }

    /// Asks your box every couple of seconds until the field is set, or the code expires.
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
            problem = "The code expired before it was entered. Try again for a new one."
        }
    }

    // MARK: - Values

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

/// A capsule button: soft white and filled for the main thing to do, outlined otherwise.
private struct SetupPill: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, primary: primary, pressed: configuration.isPressed)
    }

    private struct PillLabel<Label: View>: View {
        let label: Label
        let primary: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primary ? Color.ariBackground : .ariText)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(primary ? Color.ariText : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? Color.clear : .ariLine))
                .contentShape(Capsule())
                .opacity(pressed ? 0.6 : isEnabled ? 1 : 0.4)
        }
    }
}
