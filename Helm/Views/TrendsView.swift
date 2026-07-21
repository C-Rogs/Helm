import DesignSystem
import SwiftUI

struct TrendsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: HelmSpacing.md) {
                Text("Trend charts will appear here.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(HelmSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Trends")
        }
    }
}

#Preview {
    TrendsView()
        .helmTheme()
}
