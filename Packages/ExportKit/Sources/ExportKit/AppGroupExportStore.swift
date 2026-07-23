import Foundation

public enum AppGroupExportStore: Sendable {
    public static let appGroupID = "group.com.cameronro.helm"
    public static let latestExportFilename = "latest_schema_v2_export.json"
    public static let importURLString = "helm://import/latest"
    private static let pendingImportKey = "pending_schema_v2_share_import"

    public static var importURL: URL? {
        URL(string: importURLString)
    }

    public static func matchesImportURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "helm" else { return false }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        return (host == "import" && (path == "/latest" || path.isEmpty))
            || url.absoluteString.lowercased().hasPrefix("helm://import")
    }

    public static func markPendingImport() {
        sharedDefaults()?.set(true, forKey: pendingImportKey)
    }

    public static func consumePendingImport() -> Bool {
        guard let defaults = sharedDefaults() else { return false }
        let pending = defaults.bool(forKey: pendingImportKey)
        if pending {
            defaults.set(false, forKey: pendingImportKey)
        }
        return pending
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    public static func latestExportURL() -> URL? {
        containerURL()?.appendingPathComponent(latestExportFilename)
    }

    public static func writeLatestExport(_ data: Data) throws {
        guard let url = latestExportURL() else {
            throw AppGroupExportStoreError.containerUnavailable
        }
        try data.write(to: url, options: .atomic)
    }

    public static func readLatestExport() throws -> Data? {
        guard let url = latestExportURL() else {
            throw AppGroupExportStoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public static func clearLatestExport() throws {
        guard let url = latestExportURL() else {
            throw AppGroupExportStoreError.containerUnavailable
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        sharedDefaults()?.set(false, forKey: pendingImportKey)
    }
}

public enum AppGroupExportStoreError: Error, Equatable, Sendable {
    case containerUnavailable
}
