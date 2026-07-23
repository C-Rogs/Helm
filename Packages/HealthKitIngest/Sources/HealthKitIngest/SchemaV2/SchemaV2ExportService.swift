import ExportKit
import Foundation

public enum SchemaV2ExportService: Sendable {
    public static func buildExport(
        window: SchemaV2ExportWindow,
        inclusion: MetricInclusion = MetricInclusion(),
        exportDate: Date = Date(),
        fetcher: SchemaV2HealthKitFetcher = SchemaV2HealthKitFetcher()
    ) async throws -> (ExportPayload, Data) {
        guard window.isValid else {
            throw SchemaV2ExportError.invalidWindow
        }

        let authResult = await fetcher.requestAuthorization()
        let logs = try await fetcher.fetchDailyLogs(window: window, inclusion: inclusion)
        let status = SchemaV2ExportPipeline.resolveHealthKitStatus(
            authResult: authResult,
            logs: logs,
            inclusion: inclusion
        )
        let payload = SchemaV2ExportPipeline.buildPayload(
            window: window,
            inclusion: inclusion,
            logs: logs,
            healthKitStatus: status,
            exportDate: exportDate
        )
        let data = try SchemaV2Encoder.encode(payload, style: .humanReadable)
        return (payload, data)
    }

    public static func importSharedExport() throws -> ExportPayload? {
        guard let data = try AppGroupExportStore.readLatestExport() else {
            return nil
        }
        let payload = try SchemaV2Decoder.decode(from: data)
        try SchemaV2Validation.validate(payload)
        return payload
    }
}
