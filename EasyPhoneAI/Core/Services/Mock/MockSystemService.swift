import Foundation
import Synchronization

/// Records copies and opened URLs (D-206).
final class MockSystemService: SystemService {
    private struct State { var copied: [String] = []; var opened: [URL] = []; var canOpen = true }
    private let state = Mutex(State())

    init(canOpen: Bool = true) { state.withLock { $0.canOpen = canOpen } }

    var copied: [String] { state.withLock { $0.copied } }
    var opened: [URL] { state.withLock { $0.opened } }

    func open(_ url: URL) async -> Bool {
        state.withLock { s in
            guard s.canOpen else { return false }
            s.opened.append(url)
            return true
        }
    }

    func canOpen(_ url: URL) async -> Bool { state.withLock { $0.canOpen } }
    func copy(_ text: String) async { state.withLock { $0.copied.append(text) } }
}
