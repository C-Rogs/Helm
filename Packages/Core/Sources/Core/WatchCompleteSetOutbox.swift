import Foundation

/// Durable Watch-side queue for set-completion events before WCSession delivery.
public struct WatchCompleteSetOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable, Equatable {
        case pending
        case sent
    }

    public var id: String { eventID }
    public let eventID: String
    public let sessionExerciseID: String
    public let setID: String
    public let createdAt: TimeInterval
    public var status: Status
    public var attemptCount: Int

    public init(
        eventID: String,
        sessionExerciseID: String,
        setID: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        status: Status = .pending,
        attemptCount: Int = 0
    ) {
        self.eventID = eventID
        self.sessionExerciseID = sessionExerciseID
        self.setID = setID
        self.createdAt = createdAt
        self.status = status
        self.attemptCount = attemptCount
    }
}

/// File-backed outbox. Thread-safe. Survives Watch process death.
public final class WatchCompleteSetOutbox: @unchecked Sendable {
    public static let defaultFileName = "watch_complete_set_outbox.json"

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [WatchCompleteSetOutboxEntry]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.entries = Self.load(from: fileURL)
    }

    public convenience init(directoryURL: URL, fileName: String = WatchCompleteSetOutbox.defaultFileName) {
        let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        self.init(fileURL: url)
    }

    /// Application Support directory for the current process (Watch or tests).
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = root.appendingPathComponent("HelmWatchSync", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Unacked entries (pending or sent), oldest first.
    public var pending: [WatchCompleteSetOutboxEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.createdAt < $1.createdAt }
    }

    public var depth: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public func hasUnacked(setID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.contains { $0.setID == setID }
    }

    public func unackedSetIDs() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(entries.map(\.setID))
    }

    @discardableResult
    public func enqueue(
        eventID: String = UUID().uuidString,
        sessionExerciseID: String,
        setID: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) -> WatchCompleteSetOutboxEntry {
        lock.lock()
        defer { lock.unlock() }
        let entry = WatchCompleteSetOutboxEntry(
            eventID: eventID,
            sessionExerciseID: sessionExerciseID,
            setID: setID,
            createdAt: createdAt,
            status: .pending,
            attemptCount: 0
        )
        entries.append(entry)
        persistLocked()
        return entry
    }

    public func markSent(eventID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.eventID == eventID }) else { return }
        entries[index].status = .sent
        entries[index].attemptCount += 1
        persistLocked()
    }

    public func markAcked(eventID: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.eventID == eventID }
        persistLocked()
    }

    private func persistLocked() {
        Self.save(entries, to: fileURL)
    }

    private static func load(from url: URL) -> [WatchCompleteSetOutboxEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchCompleteSetOutboxEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [WatchCompleteSetOutboxEntry], to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
