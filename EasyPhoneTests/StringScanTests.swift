import Foundation
import Testing

/// 1G.9 (UI_SCREENS §11, D-003, D-249): every visible literal in the sources is a catalog key, and every backend error
/// code has an `error.<code>` text. Reads the repo files (the Simulator can read the Mac's paths).
@Suite("String scan (1G.9)")
struct StringScanTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func keys(_ catalog: String) throws -> Set<String> {
        let data = try Data(contentsOf: repo.appending(path: catalog))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set((json?["strings"] as? [String: Any] ?? [:]).keys)
    }

    static func swiftFiles(_ folder: String) -> [URL] {
        let root = repo.appending(path: folder)
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return items.filter { $0.pathExtension == "swift" }
    }

    /// `Text("x")`, `Button("x")`, `Label("x", …)`, `Toggle("x"`, `PrimaryButton("x"`, `SecondaryButton("x"`,
    /// `TextLinkButton("x"`, `.navigationTitle("x")` — the first argument when it is a plain string literal.
    static let pattern = try! NSRegularExpression(
        pattern: #"\b(Text|Button|Label|Toggle|PrimaryButton|SecondaryButton|TextLinkButton|navigationTitle|EmptyState\(systemImage: "[^"]*", titleKey:)\(\s*"([^"\\]*)""#)

    static func literals(in file: URL) -> [(line: Int, text: String)] {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var found: [(Int, String)] = []
        for (index, line) in source.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || line.contains("#Preview") { continue }
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let r = Range(match.range(at: match.numberOfRanges - 1), in: line) else { continue }
                found.append((index + 1, String(line[r])))
            }
        }
        return found
    }

    @Test func everyVisibleLiteralIsACatalogKey() throws {
        let appKeys = try Self.keys("EasyPhoneAI/Resources/Localizable.xcstrings")
        let widgetKeys = try Self.keys("Widgets/Localizable.xcstrings")
        var missing: [String] = []
        for (folder, keys) in [("EasyPhoneAI", appKeys), ("Widgets", widgetKeys)] {
            for file in Self.swiftFiles(folder) {
                for (line, text) in Self.literals(in: file) where !text.isEmpty && !keys.contains(text) {
                    missing.append("\(file.lastPathComponent):\(line) \"\(text)\"")
                }
            }
        }
        #expect(missing.isEmpty, "not catalog keys (D-003): \(missing)")
        #expect(!Self.swiftFiles("EasyPhoneAI").isEmpty)                         // the scan really read files
    }

    /// `LocalizedStringKey("perm.\(x).feature")` builds the key `perm.%@.feature` (interpolation = format argument), so
    /// the row shows the raw key. Build a `String` first (found on the owner's iPhone, 2026-11-19).
    @Test func noInterpolatedLocalizedStringKey() {
        let bad = try! NSRegularExpression(pattern: #"LocalizedStringKey\("[^"]*\\\("#)
        var found: [String] = []
        for folder in ["EasyPhoneAI", "Widgets"] {
            for file in Self.swiftFiles(folder) {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for (index, line) in source.components(separatedBy: .newlines).enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                    && bad.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(found.isEmpty, "interpolated LocalizedStringKey: \(found)")
    }

    @Test func everyBackendErrorCodeHasAText() throws {
        let appKeys = try Self.keys("EasyPhoneAI/Resources/Localizable.xcstrings")
        let source = try String(contentsOf: Self.repo.appending(path: "backend/app/schemas/error.py"), encoding: .utf8)
        let block = source.components(separatedBy: "ErrorCode = Literal[").last?.components(separatedBy: "]").first ?? ""
        let codes = block.matches(of: /"([a-z_]+)"/).map { String($0.output.1) }
        #expect(codes.count >= 16)
        let missing = codes.filter { !appKeys.contains("error.\($0)") }
        #expect(missing.isEmpty, "missing error.<code> (D-249): \(missing)")
        for network in ["error.network.offline", "error.generic"] { #expect(appKeys.contains(network)) }
    }
}
