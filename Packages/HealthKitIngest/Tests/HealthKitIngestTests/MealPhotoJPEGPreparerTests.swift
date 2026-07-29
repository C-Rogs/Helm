#if canImport(UIKit)
import Testing
import UIKit
@testable import HealthKitIngest

@Suite("Meal photo JPEG preparer")
struct MealPhotoJPEGPreparerTests {
    @Test("large UIImage compresses under upload limit")
    func largeImageCompressesUnderLimit() {
        let size = CGSize(width: 4_032, height: 3_024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        let prepared = MealPhotoJPEGPreparer.prepare(from: image)

        #expect(prepared != nil)
        #expect(prepared?.count ?? .max <= MealPhotoJPEGPreparer.maxJPEGBytes)
    }
}
#endif
