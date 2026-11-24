import ActivityKit
import SwiftUI
import WidgetKit

/// 4H.5 (D-337): "Bước 3/7" + the step on the Lock Screen and in the Dynamic Island while the user follows a guide in
/// another app. Started / updated / ended by the app (`LiveGuideProgressService`); tap → opens EasyPhoneK.
struct GuideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuideActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label { Text(verbatim: context.attributes.title).lineLimit(1) }
                        icon: { Image(systemName: "lightbulb.fill") }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(verbatim: context.state.label)
                        .font(.headline.monospacedDigit())
                }
                Text(verbatim: context.state.text)
                    .font(.body.weight(.semibold))
                    .lineLimit(3)
                Text("guide.activity.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .accessibilityElement(children: .combine)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "lightbulb.fill").font(.title3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: context.state.label).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(verbatim: context.state.text).font(.body).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "lightbulb.fill")
            } compactTrailing: {
                Text(verbatim: "\(context.state.step)/\(context.state.total)").monospacedDigit()
            } minimal: {
                Text(verbatim: "\(context.state.step)").monospacedDigit()
            }
        }
    }
}
