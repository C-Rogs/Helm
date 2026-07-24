import Core
import Foundation
import GRDB

struct PendingFoodImportRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_food_import"

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case barcode
        case photoMealID = "photo_meal_id"
        case provisionalLineItemsJSON = "provisional_line_items_json"
        case status
    }

    var id: String
    var createdAt: String
    var barcode: String?
    var photoMealID: String?
    var provisionalLineItemsJSON: String
    var status: String

    init(importItem: PendingFoodImport) throws {
        id = importItem.id.uuidString.lowercased()
        createdAt = ISO8601Coding.string(from: importItem.createdAt)
        barcode = importItem.barcode
        photoMealID = importItem.photoMealID?.uuidString.lowercased()
        let encoded = try Self.encoder.encode(importItem.provisionalLineItems)
        guard let jsonString = String(data: encoded, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("failed to encode provisional line items")
        }
        provisionalLineItemsJSON = jsonString
        status = importItem.status.rawValue
    }

    func toValue() throws -> PendingFoodImport {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.migrationFailed("invalid pending food import id: \(id)")
        }
        guard let importStatus = PendingFoodImport.Status(rawValue: status) else {
            throw PersistenceError.migrationFailed("invalid pending food import status: \(status)")
        }
        let lineItems = try Self.decoder.decode(
            [MealLineItem].self,
            from: Data(provisionalLineItemsJSON.utf8)
        )
        return PendingFoodImport(
            id: uuid,
            createdAt: try ISO8601Coding.date(from: createdAt),
            barcode: barcode,
            photoMealID: photoMealID.flatMap(UUID.init(uuidString:)),
            provisionalLineItems: lineItems,
            status: importStatus
        )
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
