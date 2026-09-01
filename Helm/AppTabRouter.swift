import Core
import DesignSystem
import SwiftUI

struct NutritionNavigationFocus: Equatable {
    var helmDay: HelmDay
    var mealID: UUID?
    var bucket: MealBucket?
    var startSearch = false
}

@MainActor
@Observable
final class AppTabRouter {
    static let shared = AppTabRouter()

    var selectedTab: AppTab = .dashboard
    var pendingNutritionFocus: NutritionNavigationFocus?

    /// Bumped on every tab selection change so deferred loads can follow the latest switch.
    private(set) var selectionEpoch: UInt64 = 0
    private var lastSettledEpoch: UInt64 = 0

    func openNutrition(focus: NutritionNavigationFocus? = nil) {
        selectedTab = .nutrition
        pendingNutritionFocus = focus
    }

    func openTrain() {
        open(.train)
    }

    func open(_ tab: AppTab) {
        selectedTab = tab
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
