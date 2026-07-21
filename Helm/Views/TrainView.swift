import DesignSystem
import SwiftUI

struct TrainView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: HelmSpacing.lg) {
                Text("No active session")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.textSecondary)

                Button("Start workout") {}
                    .buttonStyle(.helmPrimary)
                    .padding(.horizontal, HelmSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Train")
        }
    }
}

#Preview {
    TrainView()
        .helmTheme()
}
