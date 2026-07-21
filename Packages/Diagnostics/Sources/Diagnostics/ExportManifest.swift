import Foundation

public struct ExportManifest: Codable, Sendable, Equatable {
    public let appVersion: String
    public let buildNumber: String
    public let schemaVersion: Int
    public let exerciseSeedVersion: Int
    public let deviceModel: String
    public let osVersion: String
    public let exportTimestamp: Date

    public init(
        appVersion: String,
        buildNumber: String,
        schemaVersion: Int,
        exerciseSeedVersion: Int,
        deviceModel: String,
        osVersion: String,
        exportTimestamp: Date = Date()
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.schemaVersion = schemaVersion
        self.exerciseSeedVersion = exerciseSeedVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.exportTimestamp = exportTimestamp
    }
}

public struct ExportEnvironment: Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let schemaVersion: Int
    public let exerciseSeedVersion: Int
    public let deviceModel: String
    public let osVersion: String

    public init(
        appVersion: String,
        buildNumber: String,
        schemaVersion: Int = 0,
        exerciseSeedVersion: Int = 0,
        deviceModel: String,
        osVersion: String
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.schemaVersion = schemaVersion
        self.exerciseSeedVersion = exerciseSeedVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
    }
}
