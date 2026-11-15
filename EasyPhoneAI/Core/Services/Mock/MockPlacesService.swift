import Foundation
import Synchronization

/// Scripted search results + recorded directions (D-206).
final class MockPlacesService: PlacesService {
    private struct State { var results: [PlaceResult]; var opened: [(PlaceResult, MapsApp)] = []; var failOpen = false }
    private let state: Mutex<State>

    init(_ results: [PlaceResult] = [], failOpen: Bool = false) {
        state = Mutex(State(results: results, failOpen: failOpen))
    }

    var opened: [(place: PlaceResult, app: MapsApp)] { state.withLock { $0.opened.map { ($0.0, $0.1) } } }

    func search(_ query: String, near: Coordinate?) async throws -> [PlaceResult] {
        let key = NameNormalizer.normalize(query)
        return state.withLock { s in
            key.isEmpty ? [] : s.results.filter { NameNormalizer.normalize($0.name + " " + $0.address).contains(key) }
        }
    }

    func openDirections(to place: PlaceResult, app: MapsApp) async throws {
        try state.withLock { s in
            if s.failOpen { throw ServiceError.framework(code: "maps.cannotOpen") }
            s.opened.append((place, app))
        }
    }
}
