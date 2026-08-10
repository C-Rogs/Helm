import DesignSystem
import SwiftUI

@MainActor
@Observable
final class AppTabRouter {
    static let shared = AppTabRouter()

    var selectedTab: AppTab = .dashboard

    /// Bumped on every tab selection change so deferred loads can follow the latest switch.
    private(set) var selectionEpoch: UInt64 = 0

    func openNutrition() {
        selectedTab = .nutrition
    }

    func openTrain() {
        selectedTab = .train
    }

    func noteSelectionChanged() {
        selectionEpoch &+= 1
    }

    /// Yield MainActor until tab-bar liquid glass morph likely finished.
    /// Call before heavy tab content refresh so chrome stays smooth.
    func preferChromeOverContentLoad() async {
        var epoch = selectionEpoch
        await Task.yield()
        try? await Task.sleep(for: .seconds(HelmMotion.standard))
        while !Task.isCancelled, epoch != selectionEpoch {
            epoch = selectionEpoch
            try? await Task.sleep(for: .seconds(HelmMotion.standard))
        }
    }
}
