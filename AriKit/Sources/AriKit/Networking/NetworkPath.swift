import Foundation
import Network

/// Whether the device has a usable network. Ari doesn't try to reach the server without one, and
/// reconnects the moment it returns rather than at its next scheduled retry.
public protocol NetworkPath: Sendable {
    /// The state now, then every change.
    func updates() -> AsyncStream<Bool>
}

/// The system's view, from `NWPathMonitor`.
public struct SystemNetworkPath: NetworkPath {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "io.github.akai-ito.ari.network-path"))
        }
    }
}
