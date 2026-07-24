import Foundation
import OSLog

enum OSLogExtractor {
    static let maxEntries = 5_000
    static let lookbackInterval: TimeInterval = 24 * 60 * 60
    static let shareExtensionSubsystem = "com.cameronro.helm.share"

    static func extract(subsystem: String) throws -> String {
        try extract(subsystems: [subsystem])
    }

    static func extract(subsystems: [String]) throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let cutoff = Date().addingTimeInterval(-lookbackInterval)
        let position = store.position(date: cutoff)

        var lines: [String] = []
        for subsystem in subsystems {
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = try store.getEntries(at: position, matching: predicate)

            for case let entry as OSLogEntryLog in entries {
                let timestamp = entry.date.ISO8601Format()
                let category = entry.category
                let level = entry.level.rawValue
                let composedMessage = entry.composedMessage
                lines.append("[\(timestamp)] [\(subsystem)] [\(category)] [\(level)] \(composedMessage)")
                if lines.count >= maxEntries {
                    break
                }
            }
            if lines.count >= maxEntries {
                break
            }
        }

        if lines.isEmpty {
            return "No OSLog entries for subsystems \(subsystems.joined(separator: ", ")) in the last 24 hours.\n"
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
