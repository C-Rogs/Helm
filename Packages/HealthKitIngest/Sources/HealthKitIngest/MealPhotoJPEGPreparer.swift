#if canImport(UIKit)
import UIKit

/// Downscales and compresses meal photos for vision API upload.
public enum MealPhotoJPEGPreparer {
    public static let maxJPEGBytes = 4 * 1_024 * 1_024
    public static let maxPixelDimension: CGFloat = 2_048

    public static func prepare(from image: UIImage) -> Data? {
        var dimension = maxPixelDimension
        while dimension >= 640 {
            let scaled = downscale(image, maxDimension: dimension)
            if let data = jpegDataUnderLimit(for: scaled, maxBytes: maxJPEGBytes) {
                return data
            }
            dimension *= 0.75
        }
        return nil
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxEdge = max(size.width, size.height)
        guard maxEdge > maxDimension else {
            return normalized(image)
        }

        let scale = maxDimension / maxEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func jpegDataUnderLimit(for image: UIImage, maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.88
        var lastData: Data?
        while quality >= 0.2 {
            guard let data = image.jpegData(compressionQuality: quality) else { return nil }
            lastData = data
            if data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        guard let data = lastData, data.count <= maxBytes else { return nil }
        return data
    }
}
#endif
