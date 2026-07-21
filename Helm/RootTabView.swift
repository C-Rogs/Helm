import DesignSystem
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent") {
                DashboardView()
            }
            Tab("Train", systemImage: "dumbbell.fill") {
                TrainView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill") {
                ChatView()
            }
            Tab("Trends", systemImage: "chart.xyaxis.line") {
                TrendsView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .toolbarBackground(HelmColor.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    RootTabView()
}
