import Foundation
import Observation

/// What Settings' model picker shows: the models the engine offers and the current choice, kept up
/// to date as you choose. A refresh that fails keeps what was shown before.
@MainActor
@Observable
public final class Models {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    public private(set) var list: ModelList?
    public private(set) var load = Load.loading
    /// A choice on its way to the server, so the picker can wait for it.
    public private(set) var choosing: ModelChoice?

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// The chosen model, if the engine still offers it.
    public var chosenModel: ModelOption? {
        guard let list else { return nil }
        return list.models.first { $0.id == list.chosen.model }
    }

    public func refresh() async {
        do {
            list = try await client.models()
            load = .loaded
        } catch {
            if list == nil { load = .failed(error) }
        }
    }

    /// Chooses a model and effort for the whole server. Choosing another model keeps your step if
    /// it has it, and otherwise takes its default.
    public func choose(_ choice: ModelChoice) async throws(RequestError) {
        choosing = choice
        defer { choosing = nil }
        let saved = try await client.choose(choice)
        if let list { self.list = ModelList(models: list.models, chosen: saved) }
    }

    /// The effort to keep when switching to `model`: the same step if it has one, else its default.
    public func effort(keepingStepFor model: ModelOption) -> String {
        guard let list, let current = list.models.first(where: { $0.id == list.chosen.model }),
            let step = ThinkingStep.of(list.chosen.effort, among: current.efforts.map(\.id))
        else { return model.defaultEffort }
        let ids = model.efforts.map(\.id)
        return ids.first { ThinkingStep.of($0, among: ids) == step } ?? model.defaultEffort
    }
}
