import SwiftUI

/// Design tokens (UI_SCREENS §1, P-32 / D-267). Colors live in `Assets.xcassets` under the token name.
/// 0.10 adds only what S01 needs; the remaining tokens + the contrast test come with 1A.10.
enum Tokens {
    enum Colors {
        static let bg = Color("bg")
        static let surface = Color("surface")
        static let textPrimary = Color("textPrimary")
        static let textSecondary = Color("textSecondary")
        static let primary = Color("primary")
        static let onPrimary = Color("onPrimary")
    }

    /// Dynamic Type text styles only, never fixed sizes (UI_SCREENS §1.2, D-268).
    enum Fonts {
        static let display = Font.largeTitle.bold()
        static let title = Font.title2.bold()
        static let button = Font.title3.weight(.semibold)
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
        static let tapTargetMin: CGFloat = 44
        static let iconHero: CGFloat = 56
    }

    enum Radius {
        static let button: CGFloat = 14
        static let card: CGFloat = 16
    }
}
