import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Persists compressed JPEG meal photos keyed by meal ID.
public enum MealPhotoStore {
    public static let folderName = "meal-photos"
    public static let thumbnailMaxDimension: CGFloat = 200

    public static func save(jpeg: Data, mealID: UUID) throws {
        let url = try fileURL(for: mealID)
        try jpeg.write(to: url, options: .atomic)
    }

    public static func load(mealID: UUID) throws -> Data? {
        let url = try fileURL(for: mealID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public static func fileURL(for mealID: UUID) throws -> URL {
        try photosDirectory().appendingPathComponent("\(mealID.uuidString.lowercased()).jpg")
    }

    public static func exists(mealID: UUID) -> Bool {
        guard let url = try? fileURL(for: mealID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    public static func delete(mealID: UUID) throws -> Bool {
        let url = try fileURL(for: mealID)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    public static func copy(from sourceMealID: UUID, to targetMealID: UUID) throws {
        guard let jpeg = try load(mealID: sourceMealID) else { return }
        try save(jpeg: jpeg, mealID: targetMealID)
    }

    #if canImport(UIKit)
    public static func loadImage(mealID: UUID) -> UIImage? {
        guard let data = try? load(mealID: mealID) else { return nil }
        return UIImage(data: data)
    }

    public static func loadThumbnail(mealID: UUID, maxDimension: CGFloat = thumbnailMaxDimension) -> UIImage? {
        guard let data = try? load(mealID: mealID),
              let image = UIImage(data: data) else {
            return nil
        }
        return downscale(image, maxDimension: maxDimension)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxEdge = max(size.width, size.height)
        guard maxEdge > maxDimension else { return image }

        let scale = maxDimension / maxEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif

    private static func photosDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
