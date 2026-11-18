import AppIntents
import SwiftUI
import WidgetKit

/// 1E.4 (D-170): iOS 18 control for Control Center and the two Lock Screen buttons (instead of flashlight / camera).
/// One tap opens the app listening via `easyphone://listen`.
struct ListenControl: ControlWidget {
    static let kind = "vn.namkhanh.easyphone.listenControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(Listen.url)) {
                Label { Text("control.listen") } icon: { Image(systemName: "mic.fill") }
            }
        }
        .displayName("control.listen")
        .description("widget.desc")
    }
}
