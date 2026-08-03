import SwiftUI

/// Tron-inspired Signal chrome: void fill, neon accent brackets, faint circuit grid.
/// Uses the brand accent only (no second hue).
enum SignalChrome {
    static let cornerLength: CGFloat = 14
    static let strokeWidth: CGFloat = 1.25
    static let gridSpacing: CGFloat = 28

    static func panelFill(palette: HelmPalette) -> Color {
        palette.canvas.opacity(0.55)
    }

    static func glow(palette: HelmPalette, intensity: Double = 0.55) -> Color {
        palette.accent.opacity(intensity)
    }

    static func gridLine(palette: HelmPalette) -> Color {
        palette.accent.opacity(0.07)
    }
}

/// Full-bleed circuit grid behind Signal screens.
public struct SignalGridBackground: View {
    @Environment(\.helmPalette) private var palette

    public init() {}

    public var body: some View {
        Canvas { context, size in
            let step = SignalChrome.gridSpacing
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(SignalChrome.gridLine(palette: palette)), lineWidth: 0.5)

            // Horizon scan: one brighter horizontal near the top third.
            var scan = Path()
            let scanY = size.height * 0.28
            scan.move(to: CGPoint(x: 0, y: scanY))
            scan.addLine(to: CGPoint(x: size.width, y: scanY))
            context.stroke(scan, with: .color(palette.accent.opacity(0.14)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// HUD corner brackets + neon edge for Signal panels.
public struct SignalHUDFrame: View {
    @Environment(\.helmPalette) private var palette
    var emphasized: Bool = false

    public init(emphasized: Bool = false) {
        self.emphasized = emphasized
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let L = min(SignalChrome.cornerLength, min(w, h) * 0.28)
            let stroke = emphasized ? palette.accent.opacity(0.95) : palette.accent.opacity(0.7)

            ZStack {
                // Soft neon bloom behind the stroke.
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(stroke.opacity(0.22), lineWidth: 4)
                    .blur(radius: 3)

                Path { path in
                    // Top-left
                    path.move(to: CGPoint(x: 0, y: L))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: L, y: 0))
                    // Top-right
                    path.move(to: CGPoint(x: w - L, y: 0))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.addLine(to: CGPoint(x: w, y: L))
                    // Bottom-right
                    path.move(to: CGPoint(x: w, y: h - L))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w - L, y: h))
                    // Bottom-left
                    path.move(to: CGPoint(x: L, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h - L))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: SignalChrome.strokeWidth, lineJoin: .miter))

                // Mid-edge ticks.
                Path { path in
                    let midX = w / 2
                    let midY = h / 2
                    let tick: CGFloat = 5
                    path.move(to: CGPoint(x: midX - tick, y: 0))
                    path.addLine(to: CGPoint(x: midX + tick, y: 0))
                    path.move(to: CGPoint(x: midX - tick, y: h))
                    path.addLine(to: CGPoint(x: midX + tick, y: h))
                    path.move(to: CGPoint(x: 0, y: midY - tick))
                    path.addLine(to: CGPoint(x: 0, y: midY + tick))
                    path.move(to: CGPoint(x: w, y: midY - tick))
                    path.addLine(to: CGPoint(x: w, y: midY + tick))
                }
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public struct SignalPanelModifier: ViewModifier {
    @Environment(\.helmPalette) private var palette
    var emphasized: Bool

    public init(emphasized: Bool = false) {
        self.emphasized = emphasized
    }

    public func body(content: Content) -> some View {
        content
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(SignalChrome.panelFill(palette: palette))
            }
            .overlay {
                SignalHUDFrame(emphasized: emphasized)
            }
            .shadow(color: SignalChrome.glow(palette: palette, intensity: emphasized ? 0.35 : 0.18), radius: emphasized ? 10 : 6, y: 0)
    }
}

public extension View {
    /// Tron HUD panel treatment for Signal skin content.
    func signalHUDPanel(emphasized: Bool = false) -> some View {
        modifier(SignalPanelModifier(emphasized: emphasized))
    }
}
