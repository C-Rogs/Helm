import DesignSystem
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case nutrition
    case chat
    case settings
}

struct RootTabView: View {
    @Bindable private var tabRouter = AppTabRouter.shared
    @Bindable private var chatController = ChatBootstrap.controller

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Train", systemImage: "dumbbell.fill", value: AppTab.train) {
                TrainView()
            }
            Tab("Nutrition", systemImage: "fork.knife", value: AppTab.nutrition) {
                NutritionView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                ChatView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .toolbarBackground(HelmColor.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: tabRouter.selectedTab) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticEngine.shared.play(.selection)
        }
        .onChange(of: chatController.handoffGeneration) { _, _ in
            guard chatController.pendingHandoffPrompt != nil else { return }
            tabRouter.selectedTab = .chat
        }
    }
}

#Preview {
    RootTabView()
        .helmTheme()
}
