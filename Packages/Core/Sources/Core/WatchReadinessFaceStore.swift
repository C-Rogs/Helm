import Foundation

/// App Group snapshot for the Watch ARC complication. Written by the Watch app when
/// readiness arrives over WCSession; read by HelmWatchWidgets.
public enum WatchReadinessFaceStore: Sendable {
    public static let suiteName = "group.com.cameronro.helm.watch"
    public static let scoreKey = "arc.score"
    public static let bandKey = "arc.band"
    public static let updatedAtKey = "arc.updatedAt"

    public struct Snapshot: Equatable, Sendable {
        public var score: Int?
        public var band: String?
        public var updatedAt: TimeInterval

        public init(score: Int?, band: String?, updatedAt: TimeInterval) {
            self.score = score
            self.band = band
            self.updatedAt = updatedAt
        }
    }

    public static func makeDefaults() -> UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public static func save(
        score: Int?,
        band: String?,
        now: TimeInterval = Date().timeIntervalSince1970,
        defaults: UserDefaults? = makeDefaults()
    ) {
        guard let defaults else { return }
        if let score {
            defaults.set(score, forKey: scoreKey)
        } else {
            defaults.removeObject(forKey: scoreKey)
        }
        if let band {
            defaults.set(band, forKey: bandKey)
        } else {
            defaults.removeObject(forKey: bandKey)
        }
        defaults.set(now, forKey: updatedAtKey)
    }

    public static func load(defaults: UserDefaults? = makeDefaults()) -> Snapshot? {
        guard let defaults else { return nil }
        let score = defaults.object(forKey: scoreKey) as? Int
        let band = defaults.string(forKey: bandKey)
        let updatedAt = defaults.object(forKey: updatedAtKey) as? TimeInterval
        guard score != nil || band != nil || updatedAt != nil else { return nil }
        return Snapshot(score: score, band: band, updatedAt: updatedAt ?? 0)
    }
}
