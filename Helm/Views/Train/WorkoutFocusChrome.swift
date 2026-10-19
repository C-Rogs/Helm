import DesignSystem
import SwiftUI

/// Invisible Home-like hit target: swipe up or tap to reveal the system glass tab bar.
struct WorkoutFocusTabRevealHandle: View {
    var onReveal: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        // Upward flick from the bottom edge (same direction as Home).
                        guard value.translation.height < -24,
                              abs(value.translation.height) > abs(value.translation.width) else {
                            return
                        }
                        onReveal()
                    }
            )
            .onTapGesture(perform: onReveal)
            .accessibilityIdentifier("workout-focus-tab-reveal")
            .accessibilityLabel("Show tabs")
            .accessibilityHint("Reveals the tab bar")
            .accessibilityAddTraits(.isButton)
    }
}
