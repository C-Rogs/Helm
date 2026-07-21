import SwiftUI

public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.md)
                    .strokeBorder(HelmColor.border, lineWidth: 1)
            }
    }
}

#Preview("Card") {
    Card {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Readiness")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.textPrimary)
            Text("Building baseline")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.textSecondary)
        }
    }
    .padding()
    .helmTheme()
}
