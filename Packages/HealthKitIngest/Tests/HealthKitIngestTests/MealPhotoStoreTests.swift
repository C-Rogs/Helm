#if canImport(UIKit)
import Core
import Foundation
import Testing
import UIKit
@testable import HealthKitIngest

@Suite("Meal photo store")
struct MealPhotoStoreTests {
    @Test("save load delete and copy round trip")
    func saveLoadDeleteCopyRoundTrip() throws {
        let sourceID = UUID()
        let targetID = UUID()
        defer {
            try? MealPhotoStore.delete(mealID: sourceID)
            try? MealPhotoStore.delete(mealID: targetID)
        }

        let jpeg = try #require(sampleJPEG())
        try MealPhotoStore.save(jpeg: jpeg, mealID: sourceID)

        #expect(MealPhotoStore.exists(mealID: sourceID))
        #expect(try MealPhotoStore.load(mealID: sourceID) == jpeg)
        #expect(MealPhotoStore.loadThumbnail(mealID: sourceID) != nil)

        try MealPhotoStore.copy(from: sourceID, to: targetID)
        #expect(MealPhotoStore.exists(mealID: targetID))
        #expect(try MealPhotoStore.load(mealID: targetID) == jpeg)

        #expect(try MealPhotoStore.delete(mealID: sourceID))
        #expect(!MealPhotoStore.exists(mealID: sourceID))
        #expect(try MealPhotoStore.delete(mealID: targetID))
        #expect(!MealPhotoStore.exists(mealID: targetID))
    }

    private func sampleJPEG() -> Data? {
        let size = CGSize(width: 800, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return MealPhotoJPEGPreparer.prepare(from: image)
    }
}
#endif
