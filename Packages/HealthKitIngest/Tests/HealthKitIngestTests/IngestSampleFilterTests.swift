import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Ingest sample filter")
struct IngestSampleFilterTests {
    private let ownBundle = HealthKitIngest.defaultOwnBundleID

    @Test("filters Helm's own writes")
    func filtersOwnWrites() {
        #expect(IngestSampleFilter.shouldIngest(sourceBundleID: ownBundle, ownBundleID: ownBundle) == false)
        #expect(IngestSampleFilter.shouldIngest(sourceBundleID: "com.myfitnesspal.mfp", ownBundleID: ownBundle))
    }

    @Test("quantity filter drops own bundle samples")
    func quantityFilter() {
        let samples = [
            IngestQuantitySample(
                id: UUID(),
                start: Date(),
                end: Date(),
                value: 100,
                unitSymbol: "kcal",
                sourceBundleID: ownBundle
            ),
            IngestQuantitySample(
                id: UUID(),
                start: Date(),
                end: Date(),
                value: 50,
                unitSymbol: "kcal",
                sourceBundleID: "com.myfitnesspal.mfp"
            )
        ]

        let filtered = IngestSampleFilter.filterQuantitySamples(samples, ownBundleID: ownBundle)

        #expect(filtered.count == 1)
        #expect(filtered.first?.value == 50)
    }
}
