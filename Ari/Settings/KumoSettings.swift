import AriKit
import SwiftUI

/// Settings › Kumo, under the lead's own name: what it's called, and where it thinks you are.
struct KumoSettings: View {
    let model: AppModel
    let client: ItoClient?

    @State private var renaming = false
    /// The name just saved, until the server's info catches up.
    @State private var saved: String?

    private var name: String { saved ?? model.server?.leadName ?? LeadName.current }

    var body: some View {
        Section {
            Button {
                renaming = true
            } label: {
                LabeledContent("Name", value: name)
                    .foregroundStyle(.ariText)
            }
            .disabled(client == nil)
            .sheet(isPresented: $renaming) {
                RenameSheet(
                    title: "\(name)'s name", original: name,
                    footer: "What \(name) answers to, from its next message."
                ) { (newName: String) throws(RequestError) in
                    guard let client else { throw .network(.userAuthenticationRequired) }
                    saved = try await client.renameLead(to: newName).name
                    model.refreshServer()
                }
            }
            LabeledContent("Where you are", value: whereabouts)
                .foregroundStyle(.ariText)
            switch model.whereabouts.permission {
            case .notAsked:
                Button("Allow rough location", action: model.whereabouts.ask)
            case .refused:
                Button("Rough location in iOS Settings…") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .allowed:
                EmptyView()
            }
        } header: {
            Text(name)
        } footer: {
            Text(
                "Your phone tells \(name) its time zone, and its town when you allow rough location, "
                    + "for the weather on your Desk and so \(name) follows you when you travel. "
                    + "Nothing more precise leaves it.")
        }
        .listRowBackground(Color.ariSurface)
    }

    /// What the box keeps: "London · Europe/London", the time zone alone, or "Not yet".
    private var whereabouts: String {
        guard let kept = model.server?.whereabouts else {
            return model.server?.timeZone ?? "Not yet"
        }
        return [kept.area?.name, kept.timeZone].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A name to change, in a small sheet: Save sends it, and the sheet closes once the box has it.
struct RenameSheet: View {
    let title: String
    let original: String
    var footer: String?
    let save: (String) async throws(RequestError) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(
        title: String, original: String, footer: String? = nil,
        save: @escaping (String) async throws(RequestError) -> Void
    ) {
        self.title = title
        self.original = original
        self.footer = footer
        self.save = save
        _name = State(initialValue: original)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !saving && !trimmed.isEmpty && trimmed != original }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { if canSave { Task { await commit() } } }
                } footer: {
                    if let problem {
                        Text(problem)
                    } else if let footer {
                        Text(footer)
                    }
                }
                .listRowBackground(Color.ariSurface)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ariBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await commit() } }
                        .disabled(!canSave)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .tint(.ariText)
    }

    private func commit() async {
        saving = true
        problem = nil
        defer { saving = false }
        do throws(RequestError) {
            try await save(trimmed)
            dismiss()
        } catch {
            problem = "Couldn't rename it: \(error.plainWords)"
        }
    }
}
