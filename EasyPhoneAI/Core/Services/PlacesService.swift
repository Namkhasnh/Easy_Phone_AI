import Foundation

/// `coordinate` field encoding "lat,lng" (DATA_MODEL §1.6, e.g. "10.7769,106.7009").
struct Coordinate: Sendable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        self.init(latitude: lat, longitude: lng)
    }

    var encoded: String { "\(Self.round(latitude)),\(Self.round(longitude))" }

    /// 6 decimals ≈ 0.1 m: enough for directions, short in the field.
    private static func round(_ v: Double) -> String { String(format: "%.6f", v) }
}

/// One search result / destination (spec §6.9). 🔒 coordinates and saved addresses stay on the device (D-056).
struct PlaceResult: Sendable, Hashable, Identifiable {
    let name: String
    let address: String
    let coordinate: Coordinate
    var id: String { "\(name)|\(coordinate.encoded)" }
}

/// `mapsApp` field options (DATA_MODEL §4) / `AppSettings.preferredMapsApp`.
enum MapsApp: String, Sendable, CaseIterable {
    case appleMaps, googleMaps
}

/// MapKit search + directions hand-off (ARCHITECTURE §4.2, spec §6.9). Search runs on device; directions only open
/// a maps app → the step is `handedOff`, never `succeeded` (D-102).
protocol PlacesService: Sendable {
    func search(_ query: String, near: Coordinate?) async throws -> [PlaceResult]
    /// Throws `ServiceError.framework("maps.cannotOpen")` when no maps app can be opened.
    func openDirections(to place: PlaceResult, app: MapsApp) async throws
}

enum MapsURL {
    /// Apple Maps directions (always available on iPhone).
    static func apple(_ place: PlaceResult) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "daddr", value: place.coordinate.encoded),
                         URLQueryItem(name: "q", value: place.name)]
        return c?.url
    }

    /// Google Maps app; `comgooglemaps` must be in `LSApplicationQueriesSchemes` for `canOpenURL`.
    static func google(_ place: PlaceResult) -> URL? {
        var c = URLComponents(string: "comgooglemaps://")
        c?.queryItems = [URLQueryItem(name: "daddr", value: place.coordinate.encoded),
                         URLQueryItem(name: "directionsmode", value: "driving")]
        return c?.url
    }
}
