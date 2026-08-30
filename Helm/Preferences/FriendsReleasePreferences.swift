import Foundation
import Observation

@MainActor
@Observable
final class FriendsReleasePreferences {
    static let shared = FriendsReleasePreferences()
    static let advancedUnlockedKey = "helm.settings.advancedUnlocked"
    static let feedbackNameKey = "helm.feedback.fromName"

    var advancedUnlocked: Bool {
        didSet { UserDefaults.standard.set(advancedUnlocked, forKey: Self.advancedUnlockedKey) }
    }

    var feedbackFromName: String {
        didSet { UserDefaults.standard.set(feedbackFromName, forKey: Self.feedbackNameKey) }
    }

    var showsAdvanced: Bool {
        #if DEBUG
        true
        #else
        advancedUnlocked
        #endif
    }

    private init() {
        advancedUnlocked = UserDefaults.standard.bool(forKey: Self.advancedUnlockedKey)
        feedbackFromName = UserDefaults.standard.string(forKey: Self.feedbackNameKey) ?? ""
    }
}
