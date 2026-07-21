import DesignSystem
import SwiftUI

struct ChatView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: HelmSpacing.md) {
                Text("Coach chat will appear here.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(HelmSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Chat")
        }
    }
}

#Preview {
    ChatView()
        .helmTheme()
}
