import AriKit
import Synchronization

/// A network that's on until the test says otherwise.
final class FakeNetwork: NetworkPath {
    private let state = Mutex<(online: Bool, watchers: [AsyncStream<Bool>.Continuation])>(
        (true, []))

    func updates() -> AsyncStream<Bool> {
        let (updates, continuation) = AsyncStream<Bool>.makeStream()
        state.withLock { state in
            continuation.yield(state.online)
            state.watchers.append(continuation)
        }
        return updates
    }

    func set(_ online: Bool) {
        state.withLock { state in
            state.online = online
            for watcher in state.watchers { watcher.yield(online) }
        }
    }
}
