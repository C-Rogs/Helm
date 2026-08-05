import Foundation
import Observation

@MainActor
@Observable
final class SongTempoPreferences {
    static let shared = SongTempoPreferences()

    static let lookupEnabledKey = "helm.songTempo.lookupEnabled"

    /// Off by default. Spotify and the Apple Music catalog expose no tempo, so filling it
    /// in means sending track title and artist to a public music catalog.
    var lookupEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            defaults.set(lookupEnabled, forKey: Self.lookupEnabledKey)
        }
    }

    private let defaults: UserDefaults
    private var isHydrating = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lookupEnabled = defaults.bool(forKey: Self.lookupEnabledKey)
        isHydrating = false
    }
}
