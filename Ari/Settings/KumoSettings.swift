import AriKit
import SwiftUI

/// Settings › Kumo: what the lead is called.
struct KumoSettings: View {
    let model: AppModel
    let client: ItoClient?

    @State private var renaming = false
    /// The name just saved, until the server's info catches up.
    @State private var saved: String?

    private var name: String { saved ?? model.server?.leadName ?? "Kumo" }

    var body: some View {
        Section {
            Button {
                renaming = true
            } label: {
                LabeledContent("Kumo's name", value: name)
                    .foregroundStyle(.ariText)
            }
            .disabled(client == nil)
            .sheet(isPresented: $renaming) {
                RenameSheet(
                    title: "Kumo's name", original: name,
                    footer: "What Kumo answers to, from its next message."
                ) { (newName: String) throws(RequestError) in
                    guard let client else { throw .network(.userAuthenticationRequired) }
                    saved = try await client.renameLead(to: newName).name
                    model.refreshServer()
                }
            }
        } header: {
            Text("Kumo")
        }
        .listRowBackground(Color.ariSurface)
    }
}

/// Settings › Morning: when your morning starts, the earliest Kumo's first line of the day may come.
struct MorningSettings: View {
    let model: AppModel
    let client: ItoClient?

    @State private var time: Date
    /// What the box has, so a choice is sent only when it differs.
    @State private var saved: MorningTime
    @State private var problem: String?

    init(model: AppModel, client: ItoClient?) {
        self.model = model
        self.client = client
        let morning = model.server?.morning ?? .standard
        _saved = State(initialValue: morning)
        _time = State(initialValue: Self.date(morning))
    }

    var body: some View {
        Section {
            DatePicker("Not before", selection: $time, displayedComponents: .hourAndMinute)
                .disabled(client == nil)
                // A pause first, so turning the wheel sends only where it stops.
                .task(id: Self.morning(time)) { await save(Self.morning(time)) }
        } header: {
            Text("Morning")
        } footer: {
            if let problem {
                Text(problem)
            } else {
                Text(
                    "\(LeadName.current)'s first line of the day comes at the first calm moment "
                        + "after this time, however late: when you open Ito, or the first gap in "
                        + "your calendar.")
            }
        }
        .listRowBackground(Color.ariSurface)
    }

    private func save(_ chosen: MorningTime) async {
        guard chosen != saved, let client else { return }
        do {
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            return
        }
        do throws(RequestError) {
            saved = try await client.setMorning(chosen)
            problem = nil
            model.refreshServer()
        } catch {
            problem = "Couldn't save the time: \(error.plainWords)"
        }
    }

    private static func date(_ morning: MorningTime) -> Date {
        let time = morning.time ?? MorningTime.standard.time ?? (7, 30)
        return Calendar.current.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
    }

    private static func morning(_ date: Date) -> MorningTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return MorningTime(hour: parts.hour ?? 7, minute: parts.minute ?? 30)
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
