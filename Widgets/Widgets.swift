import SwiftUI
import WidgetKit

/// UI_SCREENS §7 / 1E.5: Home small + medium ("EasyPhoneK" / "Bấm để nói") and Lock Screen circular + rectangular.
/// No data: one static entry, never refreshed. Tap anywhere → `easyphone://listen`.
// TODO(spec): the medium widget's "{count} việc chưa xong" (D-244) needs an App Group to read the drafts; a free
// Apple ID cannot use App Groups (D-282), so it is left out.
struct ListenEntry: TimelineEntry {
    let date: Date
}

struct ListenProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListenEntry { ListenEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ListenEntry) -> Void) {
        completion(ListenEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ListenEntry>) -> Void) {
        completion(Timeline(entries: [ListenEntry(date: .now)], policy: .never))
    }
}

struct ListenWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2)
            }
            .accessibilityLabel(Text("widget.lock.a11y"))
        case .accessoryRectangular:
            Label { Text("widget.cta") } icon: { Image(systemName: "mic.fill") }
                .font(.headline)
                .accessibilityLabel(Text("widget.lock.a11y"))
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("widget.title")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 52, height: 52)
                        .background(Color("Honey"), in: Circle())
                    Text("widget.cta")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .minimumScaleFactor(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("widget.lock.a11y"))
        }
    }
}

struct ListenWidget: Widget {
    static let kind = "vn.namkhanh.easyphone.listen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ListenProvider()) { _ in
            ListenWidgetView()
                .containerBackground(Color("WidgetBackground"), for: .widget)
                .widgetURL(Listen.url)
        }
        .configurationDisplayName("widget.title")
        .description("widget.desc")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) { ListenWidget() } timeline: { ListenEntry(date: .now) }
#Preview(as: .accessoryCircular) { ListenWidget() } timeline: { ListenEntry(date: .now) }
