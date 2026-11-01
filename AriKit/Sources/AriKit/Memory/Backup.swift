import Foundation
import Observation

/// Settings › Memory's backup: where what Ari knows goes off the server, and backing it up to
/// GitHub. The server does the work; Ari starts it, shows the code and the install link, and
/// follows along. A refresh that fails keeps what was shown.
@MainActor
@Observable
public final class Backup {
    /// As the server last said; `nil` until it has.
    public private(set) var status: MemoryBackup?
    /// Starting or disconnecting right now.
    public private(set) var busy = false

    @ObservationIgnored private let client: ItoClient
    @ObservationIgnored private let clock: any Clock<Duration>

    public init(client: ItoClient, clock: any Clock<Duration> = ContinuousClock()) {
        self.client = client
        self.clock = clock
    }

    /// Asks the server again.
    public func refresh() async {
        if let answer = try? await client.memoryBackup() { status = answer }
    }

    /// Starts backing up to GitHub, or starts over: the answer holds the code to enter.
    public func start() async throws(RequestError) {
        busy = true
        defer { busy = false }
        status = try await client.backUpMemory()
    }

    /// Forgets the server's GitHub tokens; the repository stays.
    public func disconnect() async throws(RequestError) {
        busy = true
        defer { busy = false }
        status = try await client.stopMemoryBackup()
    }

    /// Follows a backup under way, asking every couple of seconds until it's on, stopped or off,
    /// or the task is cancelled.
    public func follow(every interval: Duration = .seconds(2)) async {
        while !Task.isCancelled, status?.state.isUnderway == true {
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            await refresh()
        }
    }
}
