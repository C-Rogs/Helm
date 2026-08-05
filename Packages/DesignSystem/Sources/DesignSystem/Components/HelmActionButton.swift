import SwiftUI

/// Lifecycle phases for a high-signal primary action.
public enum HelmActionPhase: Equatable, Sendable {
    case idle
    case loading
    case success
}

/// Primary action button with idle → loading → success morph.
///
/// Pass an explicit `phase` when the caller owns async state, or use
/// `HelmAsyncActionButton` when the button should own the lifecycle.
public struct HelmActionButton: View {
    private let title: String
    private let successTitle: String
    private let phase: HelmActionPhase
    private let action: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        phase: HelmActionPhase,
        successTitle: String = "Saved",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.phase = phase
        self.successTitle = successTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                labelContent(title)
                    .opacity(phase == .idle ? 1 : 0)

                ProgressView()
                    .tint(HelmColor.buttonPrimaryForeground)
                    .opacity(phase == .loading ? 1 : 0)

                HStack(spacing: HelmSpacing.xxs) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                    Text(successTitle)
                        .helmFont(.label)
                }
                .foregroundStyle(HelmColor.buttonPrimaryForeground)
                .opacity(phase == .success ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.md)
            .background(
                HelmColor.buttonPrimaryBackground.opacity(isEnabled ? 1 : 0.5),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
            .foregroundStyle(HelmColor.buttonPrimaryForeground)
        }
        .buttonStyle(HelmActionPressStyle())
        .disabled(phase != .idle)
        .animation(
            HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
            value: phase
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private func labelContent(_ text: String) -> some View {
        Text(text)
            .helmFont(.label)
            .foregroundStyle(HelmColor.buttonPrimaryForeground)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: title
        case .loading: "Loading"
        case .success: successTitle
        }
    }
}

/// Owns idle → loading → success for an async action that returns success.
public struct HelmAsyncActionButton: View {
    private let title: String
    private let successTitle: String
    private let action: () async -> Bool

    @State private var phase: HelmActionPhase = .idle
    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        successTitle: String = "Saved",
        action: @escaping () async -> Bool
    ) {
        self.title = title
        self.successTitle = successTitle
        self.action = action
    }

    public var body: some View {
        HelmActionButton(title, phase: phase, successTitle: successTitle) {
            guard phase == .idle else { return }
            Task { await run() }
        }
    }

    @MainActor
    private func run() async {
        phase = .loading
        let succeeded = await action()
        guard succeeded else {
            phase = .idle
            return
        }

        phase = .success
        let dwell = reduceMotion ? HelmMotion.quick : HelmMotion.standard
        try? await Task.sleep(for: .seconds(dwell))
        phase = .idle
    }
}

private struct HelmActionPressStyle: ButtonStyle {
    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.helmSkin) private var skin

    func makeBody(configuration: Configuration) -> some View {
        let scale = reduceMotion ? 1.0 : skin.pressScale
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(
                reduceMotion ? nil : HelmMotion.quickAnimation,
                value: configuration.isPressed
            )
    }
}

#if DEBUG
#Preview("Action button phases") {
    struct PreviewHarness: View {
        @State private var phase: HelmActionPhase = .idle

        var body: some View {
            VStack(spacing: HelmSpacing.md) {
                HelmActionButton("Save profile", phase: phase) {
                    phase = .loading
                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        phase = .success
                        try? await Task.sleep(for: .seconds(0.4))
                        phase = .idle
                    }
                }

                HelmAsyncActionButton("Finish workout", successTitle: "Done") {
                    try? await Task.sleep(for: .seconds(0.5))
                    return true
                }

                HelmActionButton("Loading", phase: .loading) {}
                HelmActionButton("Success", phase: .success, successTitle: "Saved") {}
            }
            .padding()
            .helmTheme()
        }
    }

    return PreviewHarness()
}

#Preview("Action button reduce motion") {
    HelmAsyncActionButton("Save") {
        try? await Task.sleep(for: .seconds(0.2))
        return true
    }
    .padding()
    .helmTheme()
    .environment(\.helmReduceMotion, true)
}
#endif
