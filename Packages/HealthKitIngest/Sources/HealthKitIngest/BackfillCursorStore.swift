import Foundation

struct BackfillCursor: Codable, Sendable, Equatable {
    var windowIdentity: String
    var anchoredStart: Date?
    var anchoredEnd: Date?
    var completedChunkIndices: Set<Int>
    var isFinished: Bool

    init(
        windowIdentity: String,
        anchoredStart: Date? = nil,
        anchoredEnd: Date? = nil,
        completedChunkIndices: Set<Int> = [],
        isFinished: Bool = false
    ) {
        self.windowIdentity = windowIdentity
        self.anchoredStart = anchoredStart
        self.anchoredEnd = anchoredEnd
        self.completedChunkIndices = completedChunkIndices
        self.isFinished = isFinished
    }
}

actor BackfillCursorStore {
    private let fileURL: URL
    private var cursor: BackfillCursor?

    init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("backfill_cursor.json", isDirectory: false)
        if let loaded = try? Self.load(from: fileURL) {
            let migrated = Self.migrated(from: loaded)
            cursor = migrated
            if migrated != loaded {
                try? Self.persist(migrated, to: fileURL)
            }
        }
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

    func anchorWindow(_ window: BackfillWindow) throws {
        var current = cursor(for: window)
        guard current.anchoredStart == nil, current.anchoredEnd == nil else { return }
        current.anchoredStart = window.start
        current.anchoredEnd = window.end
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
        try Self.persist(cursor, to: fileURL)
    }

    private static func persist(_ cursor: BackfillCursor, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cursor)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> BackfillCursor {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BackfillCursor.self, from: data)
    }

    /// Older builds keyed cursors by exact window timestamps; remap finished/default cursors to the preset id.
    private static func migrated(from loaded: BackfillCursor) -> BackfillCursor {
        guard loaded.windowIdentity != BackfillWindow.sixMonths().identityKey else {
            return loaded
        }
        let parts = loaded.windowIdentity.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              Double(parts[0]) != nil,
              Double(parts[1]) != nil
        else {
            return loaded
        }

        var migrated = loaded
        migrated.windowIdentity = BackfillWindow.sixMonths().identityKey
        return migrated
    }
}
