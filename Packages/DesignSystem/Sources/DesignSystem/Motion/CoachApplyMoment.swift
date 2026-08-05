import Observation
import SwiftUI

/// App-wide AI apply moment: accent swish + `coachAdjust` haptic, fired together.
@MainActor
@Observable
public final class CoachApplyMomentStore {
    public static let shared = CoachApplyMomentStore()

    public var isActive = false

    public init() {}

    /// Plays the coach apply wave and its paired haptic.
    public func play() {
        HapticEngine.shared.play(.coachAdjust)
        // Retrigger if already mid-wave so consecutive applies still sweep.
        isActive = false
        DispatchQueue.main.async { [weak self] in
            self?.isActive = true
        }
    }
}

public extension View {
    /// Mounts the global AI apply wave once near the app root.
    func helmCoachApplyWaveOverlay(
        store: CoachApplyMomentStore = .shared
    ) -> some View {
        modifier(CoachApplyWaveOverlayModifier(store: store))
    }
}

private struct CoachApplyWaveOverlayModifier: ViewModifier {
    @Bindable var store: CoachApplyMomentStore

    func body(content: Content) -> some View {
        content.overlay {
            HelmCoachApplyWave(isActive: $store.isActive)
        }
    }
}
