import Core
import DesignSystem
import SwiftUI

struct NutritionNavigationFocus: Equatable {
    var helmDay: HelmDay
    var mealID: UUID?
    var bucket: MealBucket?
    var startSearch = false
    var openWeeklyCheckIn = false
}

@MainActor
@Observable
final class AppTabRouter {
    static let shared = AppTabRouter()

    var selectedTab: AppTab = .dashboard
    var pendingNutritionFocus: NutritionNavigationFocus?
    var pendingOpenSettings = false
    var pendingOpenCloudFeatures = false

    /// Active workout: inactive tab bodies sleep; system tab bar stays hidden until revealed.
    private(set) var isWorkoutFocusActive = false
    /// When true during focus, liquid-glass system tab bar is visible (swipe-up / island).
    private(set) var isWorkoutTabBarRevealed = false

    /// Bumped on every tab selection change so deferred loads can follow the latest switch.
    private(set) var selectionEpoch: UInt64 = 0
    private var lastSettledEpoch: UInt64 = 0
    @ObservationIgnored private var tabBarAutoHideTask: Task<Void, Never>?

    func openNutrition(focus: NutritionNavigationFocus? = nil) {
        open(.nutrition)
        if pendingNutritionFocus != focus {
            pendingNutritionFocus = focus
        }
    }

    func openTrain() {
        open(.train)
    }

    func openProgress() {
        open(.progress)
    }

    func open(_ tab: AppTab) {
        if tab == .settings {
            wakeDestination(.dashboard)
            if !pendingOpenSettings {
                pendingOpenSettings = true
            }
            return
        }
        wakeDestination(tab)
    }

    func openCloudFeaturesSettings() {
        open(.dashboard)
        pendingOpenCloudFeatures = true
    }

    func consumePendingOpenSettings() {
        if pendingOpenSettings {
            pendingOpenSettings = false
        }
    }

    func consumePendingOpenCloudFeatures() {
        if pendingOpenCloudFeatures {
            pendingOpenCloudFeatures = false
        }
    }

    func select(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
    }

    func enterWorkoutFocus() {
        guard !isWorkoutFocusActive else { return }
        isWorkoutFocusActive = true
        cancelTabBarAutoHide()
        isWorkoutTabBarRevealed = false
        if selectedTab != .train {
            selectedTab = .train
        }
        noteSelectionChanged()
    }

    func exitWorkoutFocus() {
        guard isWorkoutFocusActive else { return }
        cancelTabBarAutoHide()
        isWorkoutFocusActive = false
        isWorkoutTabBarRevealed = false
    }

    /// Select a tab during (or outside) focus.
    func wakeDestination(_ tab: AppTab, revealTabBar: Bool = false) {
        let destination: AppTab = tab == .settings ? .dashboard : tab
        if destination == .train, isWorkoutFocusActive {
            returnToTrainFocus()
            return
        }
        if selectedTab != destination {
            selectedTab = destination
        }
        if isWorkoutFocusActive {
            if revealTabBar {
                revealWorkoutTabBar()
            } else {
                hideWorkoutTabBar()
            }
        }
        noteSelectionChanged()
    }

    func returnToTrainFocus() {
        if selectedTab != .train {
            selectedTab = .train
        }
        hideWorkoutTabBar()
        noteSelectionChanged()
    }

    func revealWorkoutTabBar() {
        guard isWorkoutFocusActive else { return }
        isWorkoutTabBarRevealed = true
        // If they open the bar and do not switch tabs, tuck it like Home.
        scheduleTabBarAutoHide(after: .seconds(3))
    }

    func hideWorkoutTabBar() {
        cancelTabBarAutoHide()
        guard isWorkoutFocusActive else { return }
        isWorkoutTabBarRevealed = false
    }

    /// After the athlete picks a tab from the revealed glass bar, tuck it away again.
    func dismissWorkoutTabBarAfterSelection() {
        guard isWorkoutFocusActive, isWorkoutTabBarRevealed else { return }
        cancelTabBarAutoHide()
        // Brief beat so liquid-glass selection morph is visible.
        scheduleTabBarAutoHide(after: .milliseconds(450))
    }

    private func scheduleTabBarAutoHide(after duration: Duration) {
        cancelTabBarAutoHide()
        tabBarAutoHideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, isWorkoutFocusActive else { return }
            isWorkoutTabBarRevealed = false
        }
    }

    private func cancelTabBarAutoHide() {
        tabBarAutoHideTask?.cancel()
        tabBarAutoHideTask = nil
    }

    func noteSelectionChanged() {
        selectionEpoch &+= 1
    }

    /// Yield MainActor until tab-bar liquid glass morph likely finished.
    /// Call before heavy tab content refresh so chrome stays smooth.
    /// Skips the delay when this tab was not just selected.
    func preferChromeOverContentLoad() async {
        let epoch = selectionEpoch
        guard epoch != lastSettledEpoch else { return }
        await Task.yield()
        try? await Task.sleep(for: .seconds(HelmMotion.standard))
        while !Task.isCancelled, epoch != selectionEpoch {
            try? await Task.sleep(for: .seconds(HelmMotion.standard))
        }
        guard !Task.isCancelled else { return }
        lastSettledEpoch = selectionEpoch
    }
}
