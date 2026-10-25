import Foundation
import Observation

/// What Settings › Capabilities shows: every capability the server has, kept up to date as you
/// switch them and set them up. A refresh that fails keeps what was shown before.
@MainActor
@Observable
public final class Capabilities {
    public enum Load: Equatable, Sendable {
        case loading
        case loaded
        case failed(RequestError)
    }

    public private(set) var all: [Capability] = []
    public private(set) var load = Load.loading
    /// Capabilities being switched right now, so their toggles wait for the server.
    public private(set) var switching: Set<CapabilityID> = []

    @ObservationIgnored private let client: ItoClient

    public init(client: ItoClient) {
        self.client = client
    }

    /// The domains of your life, in the server's order.
    public var domains: [Capability] { all.filter { $0.kind == .domain } }
    /// Ari's hands, and anything Ari doesn't know the kind of.
    public var hands: [Capability] { all.filter { $0.kind != .domain } }

    public func capability(_ id: CapabilityID) -> Capability? {
        all.first { $0.id == id }
    }

    /// Asks the server for the list again.
    public func refresh() async {
        do {
            all = try await client.capabilities().capabilities
            load = .loaded
        } catch {
            if all.isEmpty { load = .failed(error) }
        }
    }

    /// Switches a capability on or off. Off keeps its data, so on again picks up where it left off.
    public func setOn(_ id: CapabilityID, _ on: Bool) async throws(RequestError) {
        switching.insert(id)
        defer { switching.remove(id) }
        replace(try await client.switchCapability(id, on: on))
    }

    /// Saves setup. Passwords left out keep the ones saved.
    @discardableResult
    public func save(_ id: CapabilityID, values: [String: SetupValue]) async throws(RequestError)
        -> Capability
    {
        let updated = try await client.setUp(id, values: values)
        replace(updated)
        return updated
    }

    /// *Test connection*, with values that aren't saved yet.
    public func check(_ id: CapabilityID, values: [String: SetupValue]) async throws(RequestError)
        -> CheckResult
    {
        try await client.check(id, values: values)
    }

    private func replace(_ capability: Capability) {
        if let index = all.firstIndex(where: { $0.id == capability.id }) {
            all[index] = capability
        } else {
            all.append(capability)
        }
    }
}
