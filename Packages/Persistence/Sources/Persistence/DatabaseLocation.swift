import Foundation

public enum iCloudBackupPolicy: Sendable {
    case included
    case excluded

    /// HealthKit re-ingests health samples; keep local SQLite out of iCloud device backup.
    /// Use Settings export for an intentional offline copy.
    public static let `default`: Self = .excluded
}

public enum DatabaseLocation {
    public static let directoryName = "Helm"
    public static let fileName = "helm.sqlite"

    public static func defaultDatabaseURL(
        backupPolicy: iCloudBackupPolicy = .default
    ) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let helmDirectory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: helmDirectory,
            withIntermediateDirectories: true
        )
        try applyBackupPolicy(backupPolicy, to: helmDirectory)
        return helmDirectory.appendingPathComponent(fileName)
    }

    static func applyBackupPolicy(
        _ policy: iCloudBackupPolicy,
        to directoryURL: URL
    ) throws {
        var values = URLResourceValues()
        switch policy {
        case .included:
            values.isExcludedFromBackup = false
        case .excluded:
            values.isExcludedFromBackup = true
        }
        var url = directoryURL
        try url.setResourceValues(values)
    }
}
