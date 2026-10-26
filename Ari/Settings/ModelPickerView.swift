import AriKit
import SwiftUI

/// Settings › Model: the models the engine offers, and how hard Ari thinks, in its own four steps.
/// One choice for the whole server, from your next message.
struct ModelPickerView: View {
    let models: Models
    /// Called after a choice is saved, so Settings shows what the server now runs.
    var chosen: () -> Void = {}

    @State private var problem: String?

    var body: some View {
        Form {
            switch models.load {
            case .failed(let error):
                Section {
                    Text("Couldn't reach your server: \(error.plainWords)")
                        .foregroundStyle(.ariSecondary)
                    Button("Try again") { Task { await models.refresh() } }
                }
                .listRowBackground(Color.ariSurface)
            default:
                if let list = models.list {
                    modelSection(list)
                    if let model = models.chosenModel {
                        thinkingSection(model, effort: list.chosen.effort)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ariBackground)
        .navigationTitle("Model")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await models.refresh() }
        .disabled(models.choosing != nil)
    }

    private func modelSection(_ list: ModelList) -> some View {
        Section {
            ForEach(list.models) { model in
                Button {
                    choose(
                        ModelChoice(model: model.id, effort: models.effort(keepingStepFor: model)))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(model.title).foregroundStyle(.ariText)
                                if model.isDefault {
                                    Text("Default").font(.caption).foregroundStyle(.ariTertiary)
                                }
                            }
                            Text(
                                model.images ? model.summary : "\(model.summary) Can't see images."
                            )
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                            .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if model.id == list.chosen.model {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.ariText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.id == list.chosen.model ? .isSelected : [])
            }
            if models.chosenModel == nil {
                Text("Ari is set to \(list.chosen.model), which your server no longer offers.")
                    .font(.footnote)
                    .foregroundStyle(.ariSecondary)
            }
        } header: {
            Text("Model")
        }
        .listRowBackground(Color.ariSurface)
    }

    private func thinkingSection(_ model: ModelOption, effort: String) -> some View {
        let choices = model.choices(current: effort)
        let selected = choices.first { $0.effort.id == effort }
        return Section {
            Picker(
                "Thinking",
                selection: Binding(
                    get: { effort },
                    set: { choose(ModelChoice(model: model.id, effort: $0)) })
            ) {
                ForEach(choices, id: \.effort.id) { choice in
                    Text(Self.word(choice.step, effort: choice.effort)).tag(choice.effort.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        } header: {
            Text("Thinking")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let selected {
                    Text(Self.line(selected.step, effort: selected.effort))
                }
                if let problem {
                    Text(problem)
                } else {
                    Text("Applies from your next message, everywhere you use Ari.")
                }
            }
        }
        .listRowBackground(Color.ariSurface)
    }

    private func choose(_ choice: ModelChoice) {
        problem = nil
        Task {
            do throws(RequestError) {
                try await models.choose(choice)
                chosen()
            } catch {
                problem = "Couldn't change it: \(error.plainWords)"
            }
        }
    }

    /// Ari's word for a step, or the engine's level for one outside the four.
    static func word(_ step: ThinkingStep?, effort: ModelOption.Effort) -> String {
        switch step {
        case .quick: "Quick"
        case .balanced: "Balanced"
        case .thorough: "Thorough"
        case .deepest: "Deepest"
        case nil:
            switch effort.id {
            case "xhigh": "Deeper"
            case "minimal": "Quickest"
            default: effort.id.prefix(1).uppercased() + effort.id.dropFirst()
            }
        }
    }

    /// What a step means, in Ari's voice; the engine's own line for one outside the four.
    static func line(_ step: ThinkingStep?, effort: ModelOption.Effort) -> String {
        switch step {
        case .quick: "Quick: answers straight away, for everyday things."
        case .balanced: "Balanced: thinks a little first. Good for most things."
        case .thorough: "Thorough: takes longer to work things through."
        case .deepest: "Deepest: takes its time on the hardest problems."
        case nil: effort.summary
        }
    }
}
