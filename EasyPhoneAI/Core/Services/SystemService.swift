import Foundation

/// ARCHITECTURE §4.2: open other apps / URLs and use the clipboard. Hand-offs only (D-102: never a success).
protocol SystemService: Sendable {
    func open(_ url: URL) async -> Bool
    func canOpen(_ url: URL) async -> Bool
    func copy(_ text: String) async
}
