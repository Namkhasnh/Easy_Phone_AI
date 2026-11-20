import Foundation
import Testing

/// 1G.8 / D-180: every text colour on every background colour of the app's palette is ≥ 4.5:1 (WCAG AA), in light
/// and dark. Computed from the asset catalog itself (exact), not from screenshots (the audit samples pixels under
/// iOS's glass edge blur and reports false failures at AX5).
@Suite("Colour contrast (D-180)")
struct ColorContrastTests {
    static let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "EasyPhoneAI/Assets.xcassets")

    /// colour name → (light, dark) sRGB 0–1.
    static func color(_ name: String) throws -> (light: [Double], dark: [Double]) {
        let data = try Data(contentsOf: assets.appending(path: "\(name).colorset/Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var light: [Double] = [], dark: [Double] = []
        for entry in json["colors"] as? [[String: Any]] ?? [] {
            guard let comps = (entry["color"] as? [String: Any])?["components"] as? [String: String] else { continue }
            let rgb = ["red", "green", "blue"].map { key -> Double in
                let raw = comps[key] ?? "0"
                return raw.hasPrefix("0x") ? Double(Int(raw.dropFirst(2), radix: 16) ?? 0) / 255 : Double(raw) ?? 0
            }
            if entry["appearances"] == nil { light = rgb } else { dark = rgb }
        }
        return (light, dark.isEmpty ? light : dark)
    }

    static func luminance(_ c: [Double]) -> Double {
        let f = { (v: Double) in v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    }

    static func ratio(_ a: [Double], _ b: [Double]) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: ["textPrimary", "textSecondary", "primary", "danger", "warning"])
    func textColourOnEveryBackground(text: String) throws {
        let fg = try Self.color(text)
        for background in ["bg", "surface", "secondaryFill"] {
            let bg = try Self.color(background)
            #expect(Self.ratio(fg.light, bg.light) >= 4.5, "\(text) on \(background) light")
            #expect(Self.ratio(fg.dark, bg.dark) >= 4.5, "\(text) on \(background) dark")
        }
    }

    @Test func filledButtonsAndHoneyCards() throws {
        for (fg, bg) in [("onPrimary", "primary"), ("onPrimary", "danger"), ("onHoney", "honey"), ("textPrimary", "warningBg")] {
            let f = try Self.color(fg), b = try Self.color(bg)
            #expect(Self.ratio(f.light, b.light) >= 4.5 && Self.ratio(f.dark, b.dark) >= 4.5, "\(fg) on \(bg)")
        }
    }
}
