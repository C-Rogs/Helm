import SwiftUI

@MainActor
@Observable
final class AppTabRouter {
    static let shared = AppTabRouter()

    var selectedTab: AppTab = .dashboard

    func openNutrition() {
        selectedTab = .nutrition
    }

    func openTrain() {
        selectedTab = .train
    }
}
