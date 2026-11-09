import Foundation

/// The one place bytes leave the app. Tests replace it with a stub; `APIClient` owns all policy.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionTransport: HTTPTransport {
    /// D-127: 20 s per attempt (backend budget is 18 s, D-246).
    static let timeout: TimeInterval = 20

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral   // no cookies, no response cache
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.waitsForConnectivity = false             // offline fails fast (ARCHITECTURE §11)
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
