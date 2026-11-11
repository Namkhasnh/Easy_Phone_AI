import Foundation
import MapKit

/// `MKLocalSearch` on device (spec §6.9 AC1) + directions through `SystemService` (D-293). Nothing is logged but error
/// codes (D-059); the query never leaves Apple's on-device / MapKit path (no backend call).
final class LivePlacesService: PlacesService {
    private let system: any SystemService

    init(system: any SystemService) { self.system = system }

    func search(_ query: String, near: Coordinate?) async throws -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let near {
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                                                latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap(Self.result)
        } catch {
            // MKError.placemarkNotFound = no results, not a failure.
            if (error as NSError).code == MKError.placemarkNotFound.rawValue { return [] }
            throw ServiceError.framework(code: "maps.searchFailed")
        }
    }

    func openDirections(to place: PlaceResult, app: MapsApp) async throws {
        // AC3: Google Maps only "if installed"; otherwise Apple Maps.
        // TODO(spec): spec §6.9 AC3 does not say what to do when Google Maps is chosen but missing; Apple Maps is used.
        if app == .googleMaps, let url = MapsURL.google(place), await system.canOpen(url), await system.open(url) { return }
        guard let url = MapsURL.apple(place), await system.open(url) else {
            throw ServiceError.framework(code: "maps.cannotOpen")
        }
    }

    static func result(_ item: MKMapItem) -> PlaceResult? {
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let name = item.name ?? item.placemark.title ?? ""
        let address = item.placemark.title ?? name
        return PlaceResult(name: name, address: address,
                           coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
