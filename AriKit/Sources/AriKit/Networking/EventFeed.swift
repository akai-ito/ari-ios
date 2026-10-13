import Foundation

/// What the event stream brings once read: an event, or only a sign that the connection is alive.
enum FeedItem: Sendable {
    case event(Event)
    /// A ping, or an event this Ari couldn't read.
    case alive
}

enum EventFeed {
    /// Reads and decodes the stream's body away from the main actor, which only applies the result.
    static func items(from body: AsyncThrowingStream<Data, any Error>)
        -> AsyncThrowingStream<FeedItem, any Error>
    {
        AsyncThrowingStream { continuation in
            let reader = Task.detached {
                var parser = EventStreamParser()
                let decoder = JSONDecoder()
                do {
                    for try await chunk in body {
                        for item in parser.feed(chunk) {
                            switch item {
                            case .comment:
                                continuation.yield(.alive)
                            case .event(let sent):
                                // An event that can't be read is skipped. If it mattered, the next
                                // piece of text shows a gap, and the store asks for a snapshot.
                                if let event = try? decoder.decode(
                                    Event.self, from: Data(sent.data.utf8))
                                {
                                    continuation.yield(.event(event))
                                } else {
                                    continuation.yield(.alive)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}
