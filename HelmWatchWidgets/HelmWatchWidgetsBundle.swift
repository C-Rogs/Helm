import Core
import SwiftUI
import WatchConnectivity
import WidgetKit

struct HelmComplicationEntry: TimelineEntry {
    let date: Date
    let score: Int?
    let band: String?

    var displayScore: String {
        guard let score else { return "--" }
        return "\(score)"
    }
}

struct HelmComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HelmComplicationEntry {
        HelmComplicationEntry(date: .now, score: 64, band: "balanced")
    }

    func getSnapshot(in context: Context, completion: @escaping (HelmComplicationEntry) -> Void) {
        if context.isPreview {
            completion(HelmComplicationEntry(date: .now, score: 64, band: "balanced"))
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelmComplicationEntry>) -> Void) {
        let entry = currentEntry()
        let refresh = Date().addingTimeInterval(WatchSyncPayload.readinessPushThrottleInterval)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> HelmComplicationEntry {
        guard WCSession.isSupported() else {
            return HelmComplicationEntry(date: .now, score: nil, band: nil)
        }

        let session = WCSession.default
        if let payload = WatchSyncPayload.from(applicationContext: session.receivedApplicationContext) {
            return HelmComplicationEntry(
                date: .now,
                score: payload.readinessScore,
                band: payload.readinessBand
            )
        }

        return HelmComplicationEntry(date: .now, score: nil, band: nil)
    }
}

struct HelmComplicationView: View {
    let entry: HelmComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Text("ARC")
                    .font(.caption2)
                Text(entry.displayScore)
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .widgetURL(URL(string: WatchSyncPayload.briefDeepLink))
    }
}

struct HelmComplication: Widget {
    let kind = "HelmComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelmComplicationProvider()) { entry in
            HelmComplicationView(entry: entry)
        }
        .configurationDisplayName("Helm")
        .description("Today's ARC readiness. Tap for your morning brief.")
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
