import Foundation
import OSLog

enum OSLogExtractor {
    static let maxEntries = 5_000
    static let lookbackInterval: TimeInterval = 24 * 60 * 60

    static func extract(subsystem: String) throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let cutoff = Date().addingTimeInterval(-lookbackInterval)
        let position = store.position(date: cutoff)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var lines: [String] = []
        let entries = try store.getEntries(at: position, matching: predicate)

        for case let entry as OSLogEntryLog in entries {
            let timestamp = entry.date.ISO8601Format()
            let category = entry.category
            let level = entry.level.rawValue
            let composedMessage = entry.composedMessage
            lines.append("[\(timestamp)] [\(category)] [\(level)] \(composedMessage)")
            if lines.count >= maxEntries {
                break
            }
        }

        if lines.isEmpty {
            return "No OSLog entries for subsystem \(subsystem) in the last 24 hours.\n"
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
