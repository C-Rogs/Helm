import Core
import Foundation
import GRDB

struct BodyCompositionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "body_composition"

    enum CodingKeys: String, CodingKey {
        case id
        case helmDay = "helm_day"
        case massKg = "mass_kg"
        case bodyFatPercentage = "body_fat_percentage"
        case measuredAt = "measured_at"
    }

    var id: String
    var helmDay: String
    var massKg: Double
    var bodyFatPercentage: Double?
    var measuredAt: String

    init(composition: BodyComposition) {
        id = composition.id.uuidString.lowercased()
        helmDay = HelmDayColumn.encode(composition.helmDay)
        massKg = composition.mass.kilograms
        bodyFatPercentage = composition.bodyFatPercentage
        measuredAt = ISO8601Coding.string(from: composition.measuredAt)
    }

    func toValue() throws -> BodyComposition {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.migrationFailed("invalid body composition id: \(id)")
        }
        return BodyComposition(
            id: uuid,
            helmDay: try HelmDayColumn.decode(helmDay),
            mass: Mass(kilograms: massKg),
            bodyFatPercentage: bodyFatPercentage,
            measuredAt: try ISO8601Coding.date(from: measuredAt)
        )
    }
}
