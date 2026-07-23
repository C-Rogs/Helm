import Foundation

public enum SchemaV2ValidationError: Error, Equatable, Sendable {
    case invalidSchemaVersion(expected: Int, actual: Int)
    case invalidApp(expected: String, actual: String)
    case invalidPurpose(expected: String, actual: String)
}

public enum SchemaV2Validation: Sendable {
    public static let expectedApp = "bioharvest"
    public static let expectedPurpose = "time_series_coach_export"
    public static let expectedSchemaVersion = ExportPayload.currentSchemaVersion

    public static func validate(_ payload: ExportPayload) throws {
        guard payload.schemaVersion == expectedSchemaVersion else {
            throw SchemaV2ValidationError.invalidSchemaVersion(
                expected: expectedSchemaVersion,
                actual: payload.schemaVersion
            )
        }
        guard payload.app == expectedApp else {
            throw SchemaV2ValidationError.invalidApp(
                expected: expectedApp,
                actual: payload.app
            )
        }
        guard payload.purpose == expectedPurpose else {
            throw SchemaV2ValidationError.invalidPurpose(
                expected: expectedPurpose,
                actual: payload.purpose
            )
        }
    }
}

public enum SchemaV2Decoder {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func decode(from data: Data) throws -> ExportPayload {
        try makeDecoder().decode(ExportPayload.self, from: data)
    }
}
