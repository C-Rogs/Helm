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
        switch coachSurfaceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
    @Bindable private var sessionController = TrainBootstrap.sessionController

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            Tab("Dashboard", systemImage: HelmIcon.dashboard.rawValue, value: AppTab.dashboard) {
                DashboardView()
            }
            Tab(value: AppTab.train) {
                TrainView()
            } label: {
                trainTabLabel
            }
            Tab("Nutrition", systemImage: HelmIcon.nutrition.rawValue, value: AppTab.nutrition) {
                NutritionView()
            }
            Tab("Chat", systemImage: HelmIcon.chat.rawValue, value: AppTab.chat) {
                ChatView()
            }
        }
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

    private var trainTabLabel: some View {
        Label {
            Text("Train")
        } icon: {
            ZStack {
                Image(systemName: HelmIcon.train.rawValue)
                if sessionController.hasActiveSession {
                    HelmBrushedAccentRim(shape: Circle(), isLive: true)
                        .padding(-3)
                }
            }
        }
        .accessibilityLabel(sessionController.hasActiveSession ? "Train, workout active" : "Train")
    }
}

#Preview {
    RootTabView()
        .helmTheme()
}
