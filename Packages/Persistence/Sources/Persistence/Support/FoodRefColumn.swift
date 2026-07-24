import Core
import Foundation

enum FoodRefColumn {
    static func encode(_ ref: FoodProductRef) -> String {
        ref.cacheKey
    }

    static func decode(
        key: String,
        origin: String,
        externalID: String,
        displayName: String
    ) throws -> FoodProductRef {
        if let ref = FoodProductRef(cacheKey: key, displayName: displayName) {
            return ref
        }
        guard let parsedOrigin = FoodProductRef.Origin(rawValue: origin) else {
            throw PersistenceError.migrationFailed("invalid food origin: \(origin)")
        }
        return FoodProductRef(origin: parsedOrigin, externalID: externalID, displayName: displayName)
    }
}
