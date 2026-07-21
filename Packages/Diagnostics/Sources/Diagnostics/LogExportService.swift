import Foundation

public enum LogExportError: Error, Sendable, Equatable {
    case encodingFailed(String)
    case archiveFailed
}

public struct LogExportService: Sendable {
    private let log: DiagnosticsLog
    private let encoder: JSONEncoder

    public init(log: DiagnosticsLog = .shared) {
        self.log = log
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    public func exportBundle(environment: ExportEnvironment) async throws -> URL {
        let manifest = ExportManifest(
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            schemaVersion: environment.schemaVersion,
            exerciseSeedVersion: environment.exerciseSeedVersion,
            deviceModel: environment.deviceModel,
            osVersion: environment.osVersion
        )

        let entries = await log.entriesOldestFirst()
        let manifestData = try encode(manifest, label: "manifest.json")
        let ringBufferData = try encode(entries, label: "ring_buffer.json")
        let osLogData = try Data(
            OSLogExtractor.extract(subsystem: HelmSubsystem.value).utf8
        )

        let fileName = zipFileName()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try ZipWriter.writeArchive(
            entries: [
                "manifest.json": manifestData,
                "ring_buffer.json": ringBufferData,
                "oslog_extract.txt": osLogData
            ],
            to: destination
        )

        return destination
    }

    public func exportFullBackup(
        databaseFileURL: URL,
        environment: ExportEnvironment
    ) async throws -> URL {
        let manifest = ExportManifest(
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            schemaVersion: environment.schemaVersion,
            exerciseSeedVersion: environment.exerciseSeedVersion,
            deviceModel: environment.deviceModel,
            osVersion: environment.osVersion
        )

        let entries = await log.entriesOldestFirst()
        let manifestData = try encode(manifest, label: "manifest.json")
        let ringBufferData = try encode(entries, label: "ring_buffer.json")
        let osLogData = try Data(
            OSLogExtractor.extract(subsystem: HelmSubsystem.value).utf8
        )
        let databaseData = try Data(contentsOf: databaseFileURL)

        let fileName = fullBackupZipFileName()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try ZipWriter.writeArchive(
            entries: [
                "manifest.json": manifestData,
                "ring_buffer.json": ringBufferData,
                "oslog_extract.txt": osLogData,
                "helm.sqlite": databaseData
            ],
            to: destination
        )

        return destination
    }

    private func fullBackupZipFileName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "helm-backup-\(formatter.string(from: Date()))"
            .replacingOccurrences(of: ":", with: "-")
            + ".zip"
    }

    private func zipFileName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "helm-diagnostics-\(formatter.string(from: Date())).zip"
            .replacingOccurrences(of: ":", with: "-")
    }

    private func encode<T: Encodable>(_ value: T, label: String) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw LogExportError.encodingFailed(label)
        }
    }
}
