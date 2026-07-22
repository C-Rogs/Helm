import Foundation

public enum IngestSampleFilter {
    public static func shouldIngest(sourceBundleID: String?, ownBundleID: String) -> Bool {
        guard let sourceBundleID else { return true }
        return sourceBundleID != ownBundleID
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
