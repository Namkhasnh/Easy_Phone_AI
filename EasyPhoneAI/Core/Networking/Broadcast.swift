import Foundation
import Synchronization

/// Fan-out of values to any number of `AsyncStream` listeners. A listener only gets values sent after it subscribed.
final class Broadcast<Element: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])

    init() {}

    /// A new stream each access; it ends when the listener's task is cancelled.
    var stream: AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        return stream
    }

    func yield(_ value: Element) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(value)
        }
    }
}
