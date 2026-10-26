import Foundation

/// A model the agent's engine offers, as Settings' picker shows it.
public struct ModelOption: Sendable, Equatable, Identifiable, Codable {
    /// What to send as `model` to choose it.
    public let id: String
    public let title: String
    /// One line on what it's for, in the engine's words.
    public let summary: String
    /// How hard it can think, lightest first.
    public let efforts: [Effort]
    public let defaultEffort: String
    /// The engine's default model.
    public let isDefault: Bool
    /// Whether it can see photos you attach.
    public let images: Bool

    public struct Effort: Sendable, Equatable, Identifiable, Codable {
        /// Such as `low`, `medium`, `high`, `xhigh` or `max`.
        public let id: String
        /// The engine's own line about it.
        public let summary: String

        public init(id: String, summary: String) {
            self.id = id
            self.summary = summary
        }
    }

    public init(
        id: String, title: String, summary: String, efforts: [Effort], defaultEffort: String,
        isDefault: Bool = false, images: Bool = true
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.isDefault = isDefault
        self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, efforts, images
        case defaultEffort = "default_effort"
        case isDefault = "is_default"
    }
}

/// The agent's model and how hard it thinks: one choice for the whole server.
public struct ModelChoice: Sendable, Equatable, Codable {
    public let model: String
    public let effort: String

    public init(model: String, effort: String) {
        self.model = model
        self.effort = effort
    }
}

/// `GET /v0/models`: every model the engine offers, and the current choice.
public struct ModelList: Sendable, Equatable, Codable {
    public let models: [ModelOption]
    /// The choice, or the engine's default until one is made. A model the engine no longer offers
    /// stays chosen, but is missing from `models`.
    public let chosen: ModelChoice

    public init(models: [ModelOption], chosen: ModelChoice) {
        self.models = models
        self.chosen = chosen
    }
}

/// How hard Ari thinks, in its own four steps rather than the engine's levels.
public enum ThinkingStep: Int, CaseIterable, Sendable, Comparable {
    case quick, balanced, thorough, deepest

    /// The step an engine effort stands for, if it stands for one. `xhigh` stands for Deepest
    /// only on a model without `max`.
    public static func of(_ effort: String, among efforts: [String]) -> ThinkingStep? {
        switch effort {
        case "minimal": efforts.contains("low") ? nil : .quick
        case "low": .quick
        case "medium": .balanced
        case "high": .thorough
        case "max": .deepest
        case "xhigh": efforts.contains("max") ? nil : .deepest
        default: nil
        }
    }

    public static func < (lhs: ThinkingStep, rhs: ThinkingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension ModelOption {
    /// What the picker offers for this model: its efforts that stand for one of Ari's four steps,
    /// lightest first, plus `current` if it's another effort the model has (such as `xhigh` set on
    /// the server), so the choice is never hidden.
    public func choices(current: String?) -> [(effort: Effort, step: ThinkingStep?)] {
        let ids = efforts.map(\.id)
        return efforts.compactMap { effort in
            let step = ThinkingStep.of(effort.id, among: ids)
            return step != nil || effort.id == current ? (effort, step) : nil
        }
    }
}
