import SwiftUI
import WidgetKit

/// Entry points outside the app (D-170, D-172, UI_SCREENS §7): Home / Lock Screen widgets and the Control Center /
/// Lock Screen control. Every one opens `easyphone://listen` → the app starts listening (S03).
@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        ListenWidget()
        ListenControl()
        GuideLiveActivity()
    }
}

enum Listen {
    /// Handled by `EasyPhoneApp.onOpenURL` (1E.3).
    static let url = URL(string: "easyphone://listen")!
}
