import AriKit
import SwiftUI

/// Settings › Kumo, under the lead's own name: what it's called, when your morning starts, and the
/// Focus Ito last told it, in one section.
struct KumoSettings: View {
    let model: AppModel
    let client: ItoClient?

    @State private var renaming = false
    /// The name just saved, until the server's info catches up.
    @State private var saved: String?
    /// Why the morning didn't save, in place of what it's for.
    @State private var morningProblem: String?

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
            MorningPicker(model: model, client: client, problem: $morningProblem)
            FocusRow(model: model)
        } header: {
            Text(name)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(morningProblem ?? MorningPicker.footer(name))
                Text(FocusRow.footer(name))
            }
        }
        .listRowBackground(Color.ariSurface)
    }
}

/// When your morning starts, the earliest Kumo's first line of the day may come.
private struct MorningPicker: View {
    let model: AppModel
    let client: ItoClient?
    @Binding var problem: String?

    @State private var time: Date
    /// What the box has, so a choice is sent only when it differs.
    @State private var saved: MorningTime

    init(model: AppModel, client: ItoClient?, problem: Binding<String?>) {
        self.model = model
        self.client = client
        _problem = problem
        let morning = model.server?.morning ?? .standard
        _saved = State(initialValue: morning)
        _time = State(initialValue: Self.date(morning))
    }

    var body: some View {
        DatePicker("Morning starts", selection: $time, displayedComponents: .hourAndMinute)
            .disabled(client == nil)
            // A pause first, so turning the wheel sends only where it stops.
            .task(id: Self.morning(time)) { await save(Self.morning(time)) }
    }

    static func footer(_ lead: String) -> String {
        "\(lead)'s first line of the day comes at the first calm moment after your morning starts, "
            + "however late: when you open Ito, or the first gap in your calendar."
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
