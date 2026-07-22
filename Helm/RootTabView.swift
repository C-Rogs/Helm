import DesignSystem
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case chat
    case trends
    case settings
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Train", systemImage: "dumbbell.fill", value: AppTab.train) {
                TrainView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                ChatView()
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                TrendsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .toolbarBackground(HelmColor.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticEngine.shared.play(.selection)
        }
    }
}

#Preview {
    RootTabView()
        .helmTheme()
}
