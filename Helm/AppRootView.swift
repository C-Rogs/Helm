import DesignSystem
import SwiftUI

struct AppRootView: View {
    @State private var onboardingStore = OnboardingStore.shared

    var body: some View {
        Group {
            if onboardingStore.shouldPresent {
                OnboardingFlowView(onFinished: {})
            } else {
                RootTabView()
            }
        }
        .helmTheme()
    }
}

#Preview {
    AppRootView()
}
