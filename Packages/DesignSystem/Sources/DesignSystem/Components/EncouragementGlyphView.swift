import SwiftUI

public enum EncouragementGlyph: String, CaseIterable, Sendable, Hashable {
    case checkmark
    case bolt
    case arrowUp
    case flame
    case star
    case handThumbsUp
    case figureStrength
    case arrowUpCircle
    case sparkles
    case target
    case trophy
    case waveform

    public var symbolName: String {
        switch self {
        case .checkmark: "checkmark"
        case .bolt: "bolt.fill"
        case .arrowUp: "arrow.up"
        case .flame: "flame.fill"
        case .star: "star.fill"
        case .handThumbsUp: "hand.thumbsup.fill"
        case .figureStrength: "figure.strengthtraining.traditional"
        case .arrowUpCircle: "arrow.up.circle.fill"
        case .sparkles: "sparkles"
        case .target: "target"
        case .trophy: "trophy.fill"
        case .waveform: "waveform.path.ecg"
        }
    }

    public static func random(excludingLast last: EncouragementGlyph?) -> EncouragementGlyph {
        let pool = allCases.filter { $0 != last }
        return pool.randomElement() ?? .checkmark
    }
}

/// Brief floating glyph for milestone set completions.
public struct EncouragementGlyphView: View {
    private let glyph: EncouragementGlyph

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var isVisible = false

    public init(glyph: EncouragementGlyph) {
        self.glyph = glyph
    }

    public var body: some View {
        Image(systemName: glyph.symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(HelmColor.accent)
            .scaleEffect(isVisible ? 1 : 0.6)
            .opacity(isVisible ? 0 : 1)
            .offset(y: isVisible ? -18 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: play)
    }

    private func play() {
        if reduceMotion {
            isVisible = true
            return
        }

        withAnimation(HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion)) {
            isVisible = true
        }

        let fadeDelay = reduceMotion ? 0.2 : 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
            withAnimation(HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion)) {
                isVisible = false
            }
        }
    }
}

#if DEBUG
#Preview("Encouragement glyph") {
    ZStack {
        EncouragementGlyphView(glyph: .bolt)
    }
    .frame(width: 44, height: 44)
    .helmTheme()
}

#Preview("Encouragement glyph reduce motion") {
    EncouragementGlyphView(glyph: .checkmark)
        .frame(width: 44, height: 44)
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif
