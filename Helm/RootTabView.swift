import DesignSystem
import Persistence
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case train
    case nutrition
    case progress
    case chat
    case settings

    var coachSurfaceLabel: String {
        switch self {
        case .dashboard: "dashboard"
        case .train: "train"
        case .nutrition: "nutrition"
        case .progress: "progress"
        case .chat: "chat"
        case .settings: "settings"
        }
    }

    init?(coachSurfaceLabel: String) {
        switch coachSurfaceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dashboard": self = .dashboard
        case "train": self = .train
        case "nutrition": self = .nutrition
        case "progress": self = .progress
        case "chat": self = .chat
        case "settings": self = .settings
        default: return nil
        }
    }
}

struct RootTabView: View {
    @Bindable private var tabRouter = AppTabRouter.shared
    @Bindable private var chatController = ChatBootstrap.controller
    /// Bind store so session start/end reliably toggles workout focus.
    @Bindable private var activeSessionStore = TrainBootstrap.activeSessionStore

    private var hideSystemTabBar: Bool {
        tabRouter.isWorkoutFocusActive && !tabRouter.isWorkoutTabBarRevealed
    }

    private var focusTabBarVisibility: Visibility {
        guard tabRouter.isWorkoutFocusActive else { return .automatic }
        return tabRouter.isWorkoutTabBarRevealed ? .visible : .hidden
    }

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            Tab("Dashboard", systemImage: HelmIcon.dashboard.rawValue, value: AppTab.dashboard) {
                focusAwareTab(.dashboard) { DashboardView() }
            }
            Tab("Train", systemImage: HelmIcon.train.rawValue, value: AppTab.train) {
                focusAwareTab(.train) { TrainView() }
            }
            Tab("Nutrition", systemImage: HelmIcon.nutrition.rawValue, value: AppTab.nutrition) {
                focusAwareTab(.nutrition) { NutritionView() }
            }
            Tab("Progress", systemImage: HelmIcon.trends.rawValue, value: AppTab.progress) {
                focusAwareTab(.progress) { ProgressHubView() }
            }
            Tab("Chat", systemImage: HelmIcon.chat.rawValue, value: AppTab.chat) {
                focusAwareTab(.chat) { ChatView() }
            }
        }
        .background {
            // UIKit bridge: liquid-glass Tab bar often ignores SwiftUI toolbar hide on TabView.
            WorkoutFocusTabBarBridge(hideTabBar: hideSystemTabBar)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hideSystemTabBar {
                WorkoutFocusTabRevealHandle {
                    HapticEngine.shared.play(.selection)
                    tabRouter.revealWorkoutTabBar()
                }
            }
        }
        .overlay(alignment: .top) {
            if activeSessionStore.hasActiveSession {
                InAppWorkoutIsland()
                    .ignoresSafeArea(edges: .top)
            }
        }
        .onAppear {
            syncWorkoutFocus(hasSession: activeSessionStore.hasActiveSession)
        }
        .onChange(of: activeSessionStore.hasActiveSession) { _, live in
            syncWorkoutFocus(hasSession: live)
        }
        .onChange(of: tabRouter.selectedTab) { oldValue, newValue in
            guard oldValue != newValue else { return }
            tabRouter.noteSelectionChanged()
            HapticEngine.shared.play(.selection)
            // After picking from the revealed glass bar, tuck it away (Home-like).
            if tabRouter.isWorkoutFocusActive, tabRouter.isWorkoutTabBarRevealed {
                tabRouter.dismissWorkoutTabBarAfterSelection()
            }
            if newValue == .train {
                Task {
                    await tabRouter.preferChromeOverContentLoad()
                    guard !Task.isCancelled else { return }
                    // Active session already has week-ahead from start/finish paths.
                    guard !activeSessionStore.hasActiveSession else { return }
                    await WeekAheadScheduleBootstrap.store.refresh()
                }
            }
        }
        .onChange(of: chatController.handoffGeneration) { _, _ in
            guard chatController.pendingHandoffPrompt != nil else { return }
            // Reveal briefly so Chat is obvious, then selection handler tucks the bar.
            tabRouter.wakeDestination(.chat, revealTabBar: true)
        }
    }

    /// Sleep inactive tab bodies during workout focus so their `.task` loops cancel.
    /// Tab-bar visibility is applied on the tab *content* (required for iOS 18+ Tab API).
    @ViewBuilder
    private func focusAwareTab<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if !tabRouter.isWorkoutFocusActive || tabRouter.selectedTab == tab {
                content()
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .toolbarVisibility(focusTabBarVisibility, for: .tabBar)
        .background {
            WorkoutFocusTabBarBridge(hideTabBar: hideSystemTabBar)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func syncWorkoutFocus(hasSession: Bool) {
        if hasSession {
            tabRouter.enterWorkoutFocus()
        } else {
            tabRouter.exitWorkoutFocus()
        }
    }
}

#Preview {
    RootTabView()
        .helmTheme()
}
