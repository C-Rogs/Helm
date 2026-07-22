import Foundation

struct BackfillCursor: Codable, Sendable, Equatable {
    var windowIdentity: String
    var completedChunkIndices: Set<Int>
    var isFinished: Bool

    init(windowIdentity: String, completedChunkIndices: Set<Int> = [], isFinished: Bool = false) {
        self.windowIdentity = windowIdentity
        self.completedChunkIndices = completedChunkIndices
        self.isFinished = isFinished
    }
}

actor BackfillCursorStore {
    private let fileURL: URL
    private var cursor: BackfillCursor?

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("backfill_cursor.json", isDirectory: false)
        cursor = try? Self.load(from: fileURL)
    }

    func cursor(for window: BackfillWindow) -> BackfillCursor {
        if let cursor, cursor.windowIdentity == window.identityKey {
            return cursor
        }
        return BackfillCursor(windowIdentity: window.identityKey)
    }

    func markChunkComplete(_ index: Int, for window: BackfillWindow, totalChunks: Int) throws {
        var current = cursor(for: window)
        current.completedChunkIndices.insert(index)
        current.isFinished = current.completedChunkIndices.count >= totalChunks
        cursor = current
        try persist()
    }

    func reset(for window: BackfillWindow) throws {
        cursor = BackfillCursor(windowIdentity: window.identityKey)
        try persist()
    }

    func resetAll() throws {
        cursor = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() throws {
        guard let cursor else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cursor)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> BackfillCursor {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BackfillCursor.self, from: data)
    }
}
