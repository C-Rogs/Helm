import Foundation
import HealthKit

public enum HealthKitIngestError: Error, Sendable, LocalizedError {
    case healthDataUnavailable
    case backgroundDeliveryFailed(String)
    case anchorPersistenceFailed(String)
    case workoutWriteFailed
    case mealWriteFailed

    public var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Health data is not available on this device."
        case let .backgroundDeliveryFailed(identifier):
            "Background delivery failed for \(identifier)."
        case let .anchorPersistenceFailed(reason):
            "Could not persist HealthKit anchor: \(reason)."
        case .workoutWriteFailed:
            "Could not save workout to HealthKit."
        case .mealWriteFailed:
            "Could not save meal to HealthKit."
        }
    }
}

public actor HealthKitAnchorStore {
    private let fileURL: URL
    private var anchors: [String: Data] = [:]

    public init(directoryURL: URL) {
        fileURL = directoryURL.appendingPathComponent("healthkit_anchors.json", isDirectory: false)
        anchors = (try? Self.load(from: fileURL)) ?? [:]
    }

    public func anchor(for kind: HealthKitSampleKind) -> HKQueryAnchor? {
        guard let data = anchors[kind.anchorKey] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    public func save(anchor: HKQueryAnchor?, for kind: HealthKitSampleKind) throws {
        if let anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            anchors[kind.anchorKey] = data
        } else {
            anchors.removeValue(forKey: kind.anchorKey)
        }
        try persist()
    }

    public func resetAll() throws {
        anchors.removeAll()
        try persist()
    }

    public var hasPersistedAnchors: Bool {
        !anchors.isEmpty
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(anchors)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw HealthKitIngestError.anchorPersistenceFailed(error.localizedDescription)
        }
    }

    private static func load(from url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: Data].self, from: data)
    }
}
