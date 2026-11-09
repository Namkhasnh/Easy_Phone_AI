import Foundation
import Testing
import UIKit
@testable import EasyPhoneAI

/// 1A.10 — UI_SCREENS §11: "a unit test computes contrast for every §1.1 text pair (≥ 4.5)".
/// Reads the real colors from the app's asset catalog in light and dark (D-291 values, D-183).
@MainActor
@Suite("Token contrast (UI_SCREENS §1.1, D-291)")
struct TokenContrastTests {
    static let bundle = Bundle(for: MockTaskRepository.self)   // the app bundle

    static func rgb(_ name: String, _ style: UIUserInterfaceStyle) throws -> (Double, Double, Double) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let color = try #require(UIColor(named: name, in: bundle, compatibleWith: traits), "missing asset \(name)")
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(a == 1, "\(name) must be opaque (no opacity < 1 for text)")
        return (Double(r), Double(g), Double(b))
    }

    /// WCAG 2.x relative luminance + contrast ratio.
    static func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func lum(_ c: (Double, Double, Double)) -> Double { 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2) }
        let (l1, l2) = (lum(a), lum(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Foreground token on background token, as used by the components (UI_SCREENS §1.1, §2).
    nonisolated static let pairs: [(String, String)] = [
        ("textPrimary", "bg"), ("textPrimary", "surface"), ("textPrimary", "warningBg"),
        ("textSecondary", "bg"), ("textSecondary", "surface"),
        ("primary", "bg"), ("primary", "surface"), ("primary", "secondaryFill"), ("primary", "warningBg"),
        ("onPrimary", "primary"), ("onPrimary", "danger"),
        ("onHoney", "honey"),
        ("success", "bg"), ("success", "surface"), ("success", "secondaryFill"),
        ("danger", "bg"), ("danger", "surface"), ("danger", "secondaryFill"),
        ("warning", "warningBg"),
        ("border", "bg"), ("border", "surface"),
    ]

    struct Case: Sendable, CustomTestStringConvertible {
        let fg: String, bg: String, dark: Bool
        var testDescription: String { "\(fg) on \(bg) (\(dark ? "dark" : "light"))" }
    }

    nonisolated static let cases: [Case] = pairs.flatMap { p in [false, true].map { Case(fg: p.0, bg: p.1, dark: $0) } }

    @Test(arguments: cases) func textPairAtLeast4_5(_ c: Case) throws {
        let style: UIUserInterfaceStyle = c.dark ? .dark : .light
        let r = Self.ratio(try Self.rgb(c.fg, style), try Self.rgb(c.bg, style))
        #expect(r >= 4.5, "\(c.testDescription) = \(r)")
    }

    @Test func knownValuesMatchD291() throws {
        // Spot-check the table so a wrong asset edit is caught even if it still passes contrast.
        let primary = try Self.rgb("primary", .light), honeyDark = try Self.rgb("honey", .dark)
        #expect(abs(primary.0 * 255 - 0x1F) < 0.5 && abs(primary.1 * 255 - 0x5F) < 0.5 && abs(primary.2 * 255 - 0xA8) < 0.5)
        #expect(abs(honeyDark.0 * 255 - 0xE2) < 0.5 && abs(honeyDark.1 * 255 - 0xB2) < 0.5 && abs(honeyDark.2 * 255 - 0x6E) < 0.5)
    }

    @Test func honeyIsNotReadableAsTextOnBg() throws {
        // Documents why honey is fill-only (D-291): as text on light bg it fails.
        #expect(Self.ratio(try Self.rgb("honey", .light), try Self.rgb("bg", .light)) < 4.5)
    }
}
