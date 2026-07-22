import Core
import SwiftUI
import WidgetKit

struct HelmComplicationEntry: TimelineEntry {
    let date: Date
    let label: String
}

struct HelmComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HelmComplicationEntry {
        HelmComplicationEntry(date: .now, label: "--")
    }

    func getSnapshot(in context: Context, completion: @escaping (HelmComplicationEntry) -> Void) {
        completion(HelmComplicationEntry(date: .now, label: "--"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelmComplicationEntry>) -> Void) {
        let entry = HelmComplicationEntry(date: .now, label: "--")
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct HelmComplicationView: View {
    let entry: HelmComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Text("Helm")
                    .font(.caption2)
                Text(entry.label)
                    .font(.title3.weight(.semibold))
            }
        }
    }
}

struct HelmComplication: Widget {
    let kind = "HelmComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelmComplicationProvider()) { entry in
            HelmComplicationView(entry: entry)
        }
        .configurationDisplayName("Helm")
        .description("Readiness stub for M0.5.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct HelmWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HelmComplication()
    }
}
