import DesignSystem
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case nutrition
    case chat
    case settings

    var coachSurfaceLabel: String {
        switch self {
        case .dashboard: "dashboard"
        case .train: "train"
        case .nutrition: "nutrition"
        case .chat: "chat"
        case .settings: "settings"
        }
    }

    init?(coachSurfaceLabel: String) {
        switch coachSurfaceLabel {
        case "dashboard": self = .dashboard
        case "train": self = .train
        case "nutrition": self = .nutrition
        case "chat": self = .chat
        case "settings": self = .settings
        default: return nil
        }
    }
}

struct RootTabView: View {
    @Bindable private var tabRouter = AppTabRouter.shared
    @Bindable private var chatController = ChatBootstrap.controller

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            Tab("Dashboard", systemImage: HelmIcon.dashboard.rawValue, value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Train", systemImage: HelmIcon.train.rawValue, value: AppTab.train) {
                TrainView()
            }
            Tab("Nutrition", systemImage: HelmIcon.nutrition.rawValue, value: AppTab.nutrition) {
                NutritionView()
            }
            Tab("Chat", systemImage: HelmIcon.chat.rawValue, value: AppTab.chat) {
                ChatView()
            }
            Tab("Settings", systemImage: HelmIcon.settings.rawValue, value: AppTab.settings) {
                SettingsView()
            }
        }
        // Let system liquid glass own the tab bar. Opaque surface fill fights
        // the morph and makes chrome lag behind tab content work.
        .onChange(of: tabRouter.selectedTab) { oldValue, newValue in
            guard oldValue != newValue else { return }
            tabRouter.noteSelectionChanged()
            HapticEngine.shared.play(.selection)
            if newValue == .train {
                Task {
                    await tabRouter.preferChromeOverContentLoad()
                    guard !Task.isCancelled else { return }
                    await WeekAheadScheduleBootstrap.store.refresh()
                }
            }
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
