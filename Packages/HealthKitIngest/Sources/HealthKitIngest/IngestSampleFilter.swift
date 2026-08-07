import Foundation

public enum IngestSampleFilter {
    public static let phoneBundleID = "com.cameronro.helm"
    public static let watchBundleID = "com.cameronro.helm.watchkitapp"

    public static func shouldIngest(sourceBundleID: String?, ownBundleID: String) -> Bool {
        guard let sourceBundleID else { return true }
        return sourceBundleID != ownBundleID
    }

    /// Returns true when the workout should be persisted as a history row in Train.
    /// Excludes Helm phone and Watch bundles so Signal-logged sessions are not duplicated.
    public static func shouldPersistToHistory(sourceBundleID: String?) -> Bool {
        guard let sourceBundleID else { return true }
        return sourceBundleID != phoneBundleID && sourceBundleID != watchBundleID
    }

    public static func filterQuantitySamples(
        _ samples: [IngestQuantitySample],
        ownBundleID: String
    ) -> [IngestQuantitySample] {
        samples.filter { shouldIngest(sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID) }
    }

    public static func filterSleepSamples(
        _ samples: [IngestSleepSample],
        ownBundleID: String
    ) -> [IngestSleepSample] {
        samples.filter { shouldIngest(sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID) }
    }

    public static func filterWorkouts(
        _ samples: [IngestWorkoutSample],
        ownBundleID: String
    ) -> [IngestWorkoutSample] {
        samples.filter { shouldIngest(sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID) }
    }
}
