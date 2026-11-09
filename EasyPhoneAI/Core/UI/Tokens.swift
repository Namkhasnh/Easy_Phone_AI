import SwiftUI

/// Design tokens (UI_SCREENS §1). Colors = "Khoai" palette (D-291, supersedes D-267 values); they live in
/// `Assets.xcassets` under the token name (light + dark), checked by `TokenContrastTests`.
enum Tokens {
    enum Colors {
        static let bg = Color("bg")
        static let surface = Color("surface")
        static let textPrimary = Color("textPrimary")
        static let textSecondary = Color("textSecondary")
        static let primary = Color("primary")
        /// Text/icon on `primary`, and on `danger` fills (UI_SCREENS §1.1).
        static let onPrimary = Color("onPrimary")
        static let secondaryFill = Color("secondaryFill")
        /// Fill only (Khoai's fur): greeting card, mic ring, EmptyState circle. Never a text color (D-291).
        static let honey = Color("honey")
        static let onHoney = Color("onHoney")
        static let success = Color("success")
        static let warning = Color("warning")
        static let warningBg = Color("warningBg")
        static let danger = Color("danger")
        static let border = Color("border")
        static let focusRing = primary
    }

    /// Dynamic Type text styles only, never fixed sizes (UI_SCREENS §1.2, D-268).
    /// `display` / `title` / `button` use the rounded design (D-291).
    enum Fonts {
        static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title2, design: .rounded, weight: .bold)
        static let fieldValue = Font.title3
        static let button = Font.system(.title3, design: .rounded, weight: .semibold)
        static let body = Font.body
        static let label = Font.callout.weight(.semibold)
        /// Only legal text and the version number.
        static let caption = Font.footnote
    }

    /// 4pt grid (UI_SCREENS §1.3).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let screenPadding: CGFloat = 20
        static let sectionGap: CGFloat = 32
    }

    enum Size {
        static let buttonMinHeight: CGFloat = 56      // D-182
        static let rowMinHeight: CGFloat = 64
        static let tapTargetMin: CGFloat = 44
        static let micButton: CGFloat = 120           // D-182
        static let micButtonListening: CGFloat = 140
        static let iconInline: CGFloat = 24
        static let iconRow: CGFloat = 28
        static let iconHero: CGFloat = 56
        static let stepBadge: CGFloat = 32
        static let focusRing: CGFloat = 3
        /// Borders under Increase Contrast (UI_SCREENS §1.1 rules).
        static let borderIncreasedContrast: CGFloat = 2
    }

    enum Radius {
        static let button: CGFloat = 14
        static let card: CGFloat = 16
    }
}
