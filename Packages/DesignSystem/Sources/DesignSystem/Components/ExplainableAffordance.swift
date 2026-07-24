import SwiftUI

public struct ExplainableAffordance: ViewModifier {
    private let metric: ExplainableMetric
    private let onAskCoach: (String) -> Void

    @State private var isPresented = false

    public init(metric: ExplainableMetric, onAskCoach: @escaping (String) -> Void) {
        self.metric = metric
        self.onAskCoach = onAskCoach
    }

    public func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                presentSheet()
            }
            .overlay(alignment: .topTrailing) {
                Button(action: presentSheet) {
                    HelmIconView(.info, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                        .padding(HelmSpacing.xs)
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Show how this is calculated")
            }
            .sheet(isPresented: $isPresented) {
                ExplainSheet(metric: metric, onAskCoach: onAskCoach)
            }
    }

    private func presentSheet() {
        isPresented = true
    }
}

public extension View {
    func explainable(
        _ metric: ExplainableMetric,
        onAskCoach: @escaping (String) -> Void
    ) -> some View {
        modifier(ExplainableAffordance(metric: metric, onAskCoach: onAskCoach))
    }
}
