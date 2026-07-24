import Core
import Foundation

enum PhotoMealLineItemArchive {
    private static let folderName = "photo-meal-line-items"

    static func save(lineItems: [MealLineItem], mealID: UUID) throws {
        let directory = try archiveDirectory()
        let url = directory.appendingPathComponent("\(mealID.uuidString).json")
        let data = try JSONEncoder().encode(lineItems)
        try data.write(to: url, options: .atomic)
    }

    static func load(mealID: UUID) throws -> [MealLineItem] {
        let directory = try archiveDirectory()
        let url = directory.appendingPathComponent("\(mealID.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([MealLineItem].self, from: data)
    }

    private static func archiveDirectory() throws -> URL {
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
