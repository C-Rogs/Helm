import Foundation

struct IngestMetadata: Codable, Sendable, Equatable {
    var authorizationRequested: Bool
    var lastSyncFinishedAt: Date?
    var lastSyncSampleCount: Int
    var lastSyncDeletedCount: Int

    static let empty = IngestMetadata(
        authorizationRequested: false,
        lastSyncFinishedAt: nil,
        lastSyncSampleCount: 0,
        lastSyncDeletedCount: 0
    )
}

struct IngestMetadataStore: Sendable {
    private let fileURL: URL
    private var metadata: IngestMetadata

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("ingest_metadata.json", isDirectory: false)
        metadata = (try? Self.load(from: fileURL)) ?? .empty
    }

    var current: IngestMetadata { metadata }

    mutating func save(_ update: IngestMetadata) throws {
        metadata = update
        try persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> IngestMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IngestMetadata.self, from: data)
    }
}
