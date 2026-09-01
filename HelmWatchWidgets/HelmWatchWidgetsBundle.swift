import Core
import SwiftUI
import WatchConnectivity
import WidgetKit

/// Dark-profile instrument tokens. Mirrors DESIGN-SYSTEM.md; this target cannot import HelmWatch or DesignSystem.
private enum WidgetPalette {
    static let fg = Color(hex: 0xF4F3EE)
    static let fgMuted = Color(hex: 0x6B6A63)
    static let hairline = Color.white.opacity(0.09)
    static let depleted = Color(hex: 0xFF6A4D)
    static let compromised = Color(hex: 0xFFB648)
    static let ready = Color(hex: 0xD7E85A)
    static let primed = Color(hex: 0xC6F24E)
}

private enum WidgetReadinessState {
    case depleted
    case compromised
    case ready
    case primed

    static func from(score: Int) -> WidgetReadinessState {
        switch score {
        case ..<40: .depleted
        case 40 ..< 55: .compromised
        case 55 ..< 75: .ready
        default: .primed
        }
    }

    var label: String {
        switch self {
        case .depleted: "DEPLETED"
        case .compromised: "COMPROMISED"
        case .ready: "READY"
        case .primed: "PRIMED"
        }
    }

    var color: Color {
        switch self {
        case .depleted: WidgetPalette.depleted
        case .compromised: WidgetPalette.compromised
        case .ready: WidgetPalette.ready
        case .primed: WidgetPalette.primed
        }
    }
}

private enum WidgetType {
    static let circularScore: Font = .system(size: 18, weight: .bold, design: .monospaced).monospacedDigit()
    static let rectangularScore: Font = .system(size: 22, weight: .bold, design: .monospaced).monospacedDigit()
    static let cornerScore: Font = .system(size: 20, weight: .bold, design: .monospaced).monospacedDigit()
    static let inline: Font = .system(size: 14, weight: .semibold, design: .monospaced).monospacedDigit()
    static let monoTag: Font = .system(size: 9, weight: .medium, design: .monospaced)
    static let monoTagTracking: CGFloat = 1.2
}

/// 270-degree Arc marque (DESIGN-SYSTEM §3). Stroke `radius * 0.12`, capped for the complication.
private struct WidgetArc: View {
    var progress: Double
    var color: Color
    var track: Color = WidgetPalette.hairline
    var lineWidth: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = lineWidth ?? min(side * 0.12, 3.5)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .trim(from: 0, to: 0.75 * max(0, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .rotationEffect(.degrees(135))
            .frame(width: side - stroke, height: side - stroke)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct HelmComplicationEntry: TimelineEntry {
    let date: Date
    let score: Int?
    let band: String?

    var displayScore: String {
        guard let score else { return "--" }
        return "\(score)"
    }

    var scoreColor: Color {
        guard let score else { return WidgetPalette.fgMuted }
        return WidgetReadinessState.from(score: score).color
    }

    var stateLabel: String? {
        score.map { WidgetReadinessState.from(score: $0).label }
    }

    var arcProgress: Double {
        guard let score else { return 0 }
        return min(max(Double(score) / 100, 0), 1)
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
        var dayComponents = Calendar.current.dateComponents([.era, .year, .month, .day], from: Date())
        dayComponents.day? += 1
        dayComponents.hour = 6
        dayComponents.minute = 0
        let refresh = Calendar.current.date(from: dayComponents) ?? Date().addingTimeInterval(86400)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> HelmComplicationEntry {
        if let snapshot = WatchReadinessFaceStore.load(), snapshot.score != nil || snapshot.band != nil {
            return HelmComplicationEntry(
                date: .now,
                score: snapshot.score,
                band: snapshot.band
            )
        }

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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryCorner:
                corner
            case .accessoryRectangular:
                rectangular
            case .accessoryInline:
                inline
            default:
                circular
            }
        }
        .widgetURL(URL(string: WatchSyncPayload.briefDeepLink))
        .accessibilityLabel(accessibilityScoreLabel)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            WidgetArc(progress: entry.arcProgress, color: entry.scoreColor)
                .padding(2)
            VStack(spacing: 0) {
                Text(entry.displayScore)
                    .font(WidgetType.circularScore)
                    .foregroundStyle(entry.score == nil ? WidgetPalette.fgMuted : entry.scoreColor)
                Text(entry.stateLabel ?? "ARC")
                    .font(WidgetType.monoTag)
                    .tracking(WidgetType.monoTagTracking)
                    .foregroundStyle(WidgetPalette.fgMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var corner: some View {
        Text(entry.displayScore)
            .font(WidgetType.cornerScore)
            .foregroundStyle(entry.scoreColor)
            .widgetLabel {
                Text("ARC")
                    .font(WidgetType.monoTag)
                    .tracking(WidgetType.monoTagTracking)
                    .foregroundStyle(WidgetPalette.fgMuted)
            }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            WidgetArc(progress: entry.arcProgress, color: entry.scoreColor)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("ARC")
                    .font(WidgetType.monoTag)
                    .tracking(WidgetType.monoTagTracking)
                    .foregroundStyle(WidgetPalette.fgMuted)
                Text(entry.displayScore)
                    .font(WidgetType.rectangularScore)
                    .foregroundStyle(entry.score == nil ? WidgetPalette.fgMuted : WidgetPalette.fg)
                Text(entry.stateLabel ?? "Waiting for Signal")
                    .font(WidgetType.monoTag)
                    .tracking(WidgetType.monoTagTracking)
                    .foregroundStyle(WidgetPalette.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        Text("ARC \(entry.displayScore)")
            .font(WidgetType.inline)
            .foregroundStyle(entry.scoreColor)
    }

    private var accessibilityScoreLabel: String {
        if let score = entry.score, let stateLabel = entry.stateLabel {
            return "ARC \(score), \(stateLabel.lowercased())"
        }
        return "ARC unavailable. Open Signal for your brief."
    }
}

struct HelmComplication: Widget {
    let kind = "HelmComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelmComplicationProvider()) { entry in
            HelmComplicationView(entry: entry)
        }
        .configurationDisplayName("Signal")
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

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

#if DEBUG
#Preview("Circular ready", as: .accessoryCircular) {
    HelmComplication()
} timeline: {
    HelmComplicationEntry(date: .now, score: 64, band: "balanced")
}

#Preview("Circular empty", as: .accessoryCircular) {
    HelmComplication()
} timeline: {
    HelmComplicationEntry(date: .now, score: nil, band: nil)
}

#Preview("Rectangular primed", as: .accessoryRectangular) {
    HelmComplication()
} timeline: {
    HelmComplicationEntry(date: .now, score: 82, band: "primed")
}
#endif
