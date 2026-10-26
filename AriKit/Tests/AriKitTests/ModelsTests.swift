import AriKit
import Foundation
import Testing

/// Settings' model picker: Ari's four steps of thinking over the engine's levels, and choosing
/// through the real client, against the contract's transcript.
@Suite("Models")
@MainActor
struct ModelsTests {
    private static let levels = ["low", "medium", "high", "xhigh", "max"]

    private static func model(_ id: String, _ efforts: [String], default effort: String)
        -> ModelOption
    {
        ModelOption(
            id: id, title: id, summary: "",
            efforts: efforts.map { ModelOption.Effort(id: $0, summary: "\($0) line") },
            defaultEffort: effort)
    }

    @Test("four steps: low, medium, high and max, with xhigh tucked away")
    func steps() {
        let sol = Self.model("sol", Self.levels, default: "low")
        let offered = sol.choices(current: "low")
        #expect(offered.map(\.effort.id) == ["low", "medium", "high", "max"])
        #expect(offered.map(\.step) == [.quick, .balanced, .thorough, .deepest])
    }

    @Test("xhigh shows when it's the current choice, and is Deepest on a model without max")
    func xhigh() {
        let sol = Self.model("sol", Self.levels, default: "low")
        #expect(
            sol.choices(current: "xhigh").map(\.effort.id) == [
                "low", "medium", "high", "xhigh", "max",
            ])
        #expect(sol.choices(current: "xhigh").first { $0.effort.id == "xhigh" }?.step == nil)

        let older = Self.model("older", ["minimal", "medium", "high", "xhigh"], default: "medium")
        #expect(
            older.choices(current: nil).map(\.step) == [.quick, .balanced, .thorough, .deepest])
    }

    @Test("an effort Ari doesn't know only shows when it's chosen")
    func unknown() {
        let future = Self.model("future", ["low", "medium", "ultra"], default: "low")
        #expect(future.choices(current: "low").map(\.effort.id) == ["low", "medium"])
        #expect(future.choices(current: "ultra").map(\.effort.id) == ["low", "medium", "ultra"])
    }

    /// The contract's transcript, through `Models` and the real client: list, a refused effort,
    /// the choice, and the server naming it.
    @Test("plays transcript 37")
    func transcript() async throws {
        let transcript = try Fixtures.transcript("37-choose-the-model")
        let server = TranscriptServer(transcript)
        let models = Models(client: server.client)
        for case .app(let request) in transcript.steps {
            switch request.route {
            case .models:
                await models.refresh()
                #expect(models.load == .loaded)
            case .chooseModel:
                let choice = try #require(request.body).decode(ModelChoice.self)
                do {
                    try await models.choose(choice)
                    #expect(models.list?.chosen == choice)
                } catch {
                    #expect(error.status == 400)
                    #expect(models.list?.chosen != choice, "a refused choice mustn't stick")
                }
            case .server:
                let info = try await server.client.server()
                #expect(info.agent.model == models.list?.chosen.model)
                #expect(info.agent.effort == models.list?.chosen.effort)
            default:
                Issue.record("no action for \(request.method) \(request.path)")
            }
        }
        let mismatches = await server.mismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(await server.unanswered == 0)
    }

    @Test("switching model keeps your step when the new model has it")
    func keepsTheStep() async throws {
        let transcript = try Fixtures.transcript("37-choose-the-model")
        let server = TranscriptServer(transcript, only: { $0 == .models })
        let models = Models(client: server.client)
        await models.refresh()
        let luna = try #require(models.list?.models.first { $0.id == "gpt-6-luna" })
        // The default choice is gpt-6.1-sol at low (Quick); Luna's Quick is low too.
        #expect(models.effort(keepingStepFor: luna) == "low")
    }
}
