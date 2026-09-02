import Core
import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Watch instrument kit – mirrors DesignSystem dark palette, Arc,
// type, motion, and screen states. Self-contained so the watch
// target does not pull Diagnostics, UIKit, CoreHaptics, or fonts.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// MARK: - Palette (dark-only; watch is OLED)

enum WatchPalette {
    static let canvas        = Color(hex: 0x000000)
    static let surface       = Color(hex: 0x111112)
    static let surfaceElevated = Color(hex: 0x1C1C19)
    static let hairline      = Color.white.opacity(0.09)
    static let fg            = Color(hex: 0xF4F3EE)
    static let fgSecondary   = Color(hex: 0xA8A7A0)
    static let fgMuted       = Color(hex: 0x6B6A63)

    static let accent        = Color(hex: 0xC6F24E)
    static let accentFill    = Color(hex: 0xC6F24E)
    static let buttonPrimaryForeground = Color.black

    static let depleted       = Color(hex: 0xFF6A4D)
    static let compromised    = Color(hex: 0xFFB648)
    static let ready          = Color(hex: 0xD7E85A)
    static let primed         = Color(hex: 0xC6F24E)

    static func color(for state: WatchState) -> Color {
        state.color
    }
}

// MARK: - State ramp (readiness + HR effort)

enum WatchState: String {
    case depleted
    case compromised
    case ready
    case primed

    static func readiness(score: Int) -> WatchState {
        switch score {
        case ..<40: .depleted
        case 40..<55: .compromised
        case 55..<75: .ready
        default: .primed
        }
    }

    /// Effort along the state ramp (easy to hard). Always pair with a Z1-Z5 label.
    static func heartRateZone(_ zone: HeartRateZone) -> WatchState {
        switch zone {
        case .zone1: .primed
        case .zone2: .ready
        case .zone3: .compromised
        case .zone4, .zone5: .depleted
        }
    }

    var color: Color {
        switch self {
        case .depleted: WatchPalette.depleted
        case .compromised: WatchPalette.compromised
        case .ready: WatchPalette.ready
        case .primed: WatchPalette.primed
        }
    }

    var label: String { rawValue.uppercased() }
}

enum WatchReadinessBand {
    static func color(for score: Int) -> Color {
        WatchState.readiness(score: score).color
    }

    static func label(for score: Int) -> String {
        WatchState.readiness(score: score).label
    }
}

enum WatchZoneColor {
    static func color(for zone: HeartRateZone?) -> Color {
        guard let zone else { return WatchPalette.fgSecondary }
        return WatchState.heartRateZone(zone).color
    }

    static func progress(for zone: HeartRateZone?) -> Double {
        guard let zone else { return 0 }
        return Double(zone.rawValue) / Double(HeartRateZone.zone5.rawValue) * 100
    }
}

struct WatchZoneCaption: View {
    let zone: HeartRateZone?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchZoneColor.color(for: zone))
            Text(zone?.displayName ?? "HR")
                .watchType(.monoTag, color: WatchPalette.fgMuted)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Type scale (watch-adjusted; numerals always mono tabular)

enum WatchType {
    case heroNumber
    case bigNumber
    case number
    case title
    case label
    case body
    case monoTag

    var font: Font {
        switch self {
        case .heroNumber: .system(size: 36, weight: .bold, design: .monospaced).monospacedDigit()
        case .bigNumber:  .system(size: 22, weight: .bold, design: .monospaced).monospacedDigit()
        case .number:     .system(size: 15, weight: .semibold, design: .monospaced).monospacedDigit()
        case .title:      .system(size: 17, weight: .semibold)
        case .label:      .system(size: 15, weight: .semibold)
        case .body:       .system(size: 13, weight: .regular)
        case .monoTag:    .system(size: 10, weight: .medium, design: .monospaced)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .monoTag: 1.6
        default: 0
        }
    }

    var isUppercase: Bool {
        self == .monoTag
    }
}

// MARK: - Motion (pairs with Docs/HAPTICS.md; WatchKit haptics stay separate)

enum WatchSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
}

enum WatchLayout {
    static let hit: CGFloat = 44
    static let heroArc: CGFloat = 108
    static let heroArcAOD: CGFloat = 88
    static let liveDot: CGFloat = 6
    /// Keep content out from under the system time (top trailing).
    static let clockClearance: CGFloat = 52
}

enum WatchTimeFormatting {
    static func mmss(_ remainingSeconds: Int) -> String {
        let clamped = max(0, remainingSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Digit-roll time. `Text(timerInterval:)` and whole-string `mmss` tick like the system clock.
struct WatchRollingTime: View {
    let seconds: Int
    var style: WatchType = .heroNumber
    var color: Color = WatchPalette.fg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        HStack(spacing: 0) {
            Text("\(minutes)")
                .watchType(style, color: color)
                .watchNumericRoll(value: minutes, reduceMotion: reduceMotion)
            Text(":")
                .watchType(style, color: color)
            Text(String(format: "%02d", secs))
                .watchType(style, color: color)
                .watchNumericRoll(value: secs, reduceMotion: reduceMotion)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchTimeFormatting.mmss(seconds))
    }
}

enum WatchMotion {
    static let quick: TimeInterval = 0.18
    static let standard: TimeInterval = 0.28
    static let reveal: TimeInterval = 0.9

    static var quickAnimation: Animation { .easeOut(duration: quick) }
    static var standardAnimation: Animation { .easeInOut(duration: standard) }
    static var revealAnimation: Animation { .easeOut(duration: reveal) }

    static func animation(_ preferred: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? quickAnimation : preferred
    }

    static func shouldAnimateReveal(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

struct WatchNumericText: View {
    let text: String
    var style: WatchType = .heroNumber
    var color: Color = WatchPalette.fg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String, style: WatchType = .heroNumber, color: Color = WatchPalette.fg) {
        self.text = text
        self.style = style
        self.color = color
    }

    init(_ value: Int, style: WatchType = .heroNumber, color: Color = WatchPalette.fg) {
        self.init("\(value)", style: style, color: color)
    }

    var body: some View {
        Text(text)
            .watchType(style, color: color)
            .watchNumericRoll(value: text, reduceMotion: reduceMotion)
    }
}

private struct WatchNumericRollModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(.numericText())
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                } else if transaction.animation == nil {
                    transaction.animation = WatchMotion.quickAnimation
                }
            }
            .animation(
                WatchMotion.animation(WatchMotion.quickAnimation, reduceMotion: reduceMotion),
                value: value
            )
    }
}

extension View {
    func watchNumericRoll<Value: Equatable>(
        value: Value,
        reduceMotion: Bool
    ) -> some View {
        modifier(WatchNumericRollModifier(value: value, reduceMotion: reduceMotion))
    }
}

// MARK: - Arc (270deg, gap at bottom; track hairline, value = state)

struct WatchArcGauge<Center: View>: View {
    let value: Double
    var range: ClosedRange<Double> = 0 ... 100
    let state: WatchState
    var track: Color = WatchPalette.hairline
    var lineWidth: CGFloat? = nil
    let center: Center

    init(
        value: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: WatchState,
        track: Color = WatchPalette.hairline,
        lineWidth: CGFloat? = nil,
        @ViewBuilder center: () -> Center
    ) {
        self.value = value
        self.range = range
        self.state = state
        self.track = track
        self.lineWidth = lineWidth
        self.center = center()
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2
            let stroke = resolvedLineWidth(radius: radius)

            ZStack {
                arcLayer(progress: 1, color: track, lineWidth: stroke, side: side)
                arcLayer(progress: normalizedValue, color: state.color, lineWidth: stroke, side: side)
                center
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var normalizedValue: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func resolvedLineWidth(radius: CGFloat) -> CGFloat {
        if let lineWidth { return lineWidth }
        return min(radius * 0.12, 8)
    }

    private func arcLayer(
        progress: Double,
        color: Color,
        lineWidth: CGFloat,
        side: CGFloat
    ) -> some View {
        Circle()
            .trim(from: 0, to: progress * 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(135))
            .frame(width: side - lineWidth, height: side - lineWidth)
    }
}

extension WatchArcGauge where Center == EmptyView {
    init(
        value: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: WatchState,
        track: Color = WatchPalette.hairline,
        lineWidth: CGFloat? = nil
    ) {
        self.init(
            value: value,
            range: range,
            state: state,
            track: track,
            lineWidth: lineWidth
        ) {
            EmptyView()
        }
    }
}

struct WatchArcRevealGauge<Center: View>: View {
    let targetValue: Double
    var range: ClosedRange<Double> = 0 ... 100
    let state: WatchState
    let reduceMotion: Bool
    let center: (Double) -> Center

    @State private var displayValue: Double = 0

    init(
        targetValue: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: WatchState,
        reduceMotion: Bool,
        @ViewBuilder center: @escaping (Double) -> Center
    ) {
        self.targetValue = targetValue
        self.range = range
        self.state = state
        self.reduceMotion = reduceMotion
        self.center = center
    }

    var body: some View {
        WatchArcGauge(value: displayValue, range: range, state: state) {
            center(displayValue)
        }
        .onAppear(perform: beginRevealIfNeeded)
        .onChange(of: targetValue) { _, newValue in
            guard WatchMotion.shouldAnimateReveal(reduceMotion: reduceMotion) else {
                displayValue = newValue
                return
            }
            withAnimation(WatchMotion.revealAnimation) {
                displayValue = newValue
            }
        }
    }

    private func beginRevealIfNeeded() {
        if WatchMotion.shouldAnimateReveal(reduceMotion: reduceMotion) {
            displayValue = 0
            withAnimation(WatchMotion.revealAnimation) {
                displayValue = targetValue
            }
        } else {
            displayValue = targetValue
        }
    }
}

// MARK: - Screen states

struct WatchEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .watchType(.label)
                .multilineTextAlignment(.center)
            Text(message)
                .watchType(.body, color: WatchPalette.fgSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct WatchLoadingState: View {
    var message: String = "Loading"

    var body: some View {
        VStack(spacing: 6) {
            ProgressView()
                .tint(WatchPalette.accent)
            Text(message)
                .watchType(.monoTag, color: WatchPalette.fgMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel(message)
    }
}

struct WatchErrorState: View {
    var title: String = "Something went wrong"
    let message: String
    var retryTitle: String? = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Text("ERROR")
                .watchType(.monoTag, color: WatchPalette.depleted)
            Text(title)
                .watchType(.label)
                .multilineTextAlignment(.center)
            Text(message)
                .watchType(.body, color: WatchPalette.depleted)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(WatchType.label.font)
                    .tint(WatchPalette.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - View modifiers

extension View {
    func watchType(_ style: WatchType, color: Color = WatchPalette.fg) -> some View {
        self
            .font(style.font)
            .foregroundStyle(color)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }

    /// Apply Helm watch theme: OLED-black background, accent tint, system fonts.
    func helmWatchTheme() -> some View {
        self
            .tint(WatchPalette.accent)
            .background(WatchPalette.canvas)
            .preferredColorScheme(.dark)
    }

    /// Standard screen background for watch content areas.
    func helmWatchScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(WatchPalette.canvas.ignoresSafeArea())
    }
}

// MARK: - Color extension (hex init, shared with watch)

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red   = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >>  8) & 0xFF) / 255
        let blue  = Double(hex        & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
