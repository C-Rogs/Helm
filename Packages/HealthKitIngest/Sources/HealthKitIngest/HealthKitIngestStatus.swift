import Foundation

public struct HealthKitIngestStatus: Sendable, Equatable {
    public let isObserving: Bool
    public let lastSyncFinishedAt: Date?
    public let lastSyncSampleCount: Int
    public let lastSyncDeletedCount: Int
    public let authorizationRequested: Bool
    public let lastErrorMessage: String?

    public init(
        isObserving: Bool,
        lastSyncFinishedAt: Date?,
        lastSyncSampleCount: Int,
        lastSyncDeletedCount: Int,
        authorizationRequested: Bool,
        lastErrorMessage: String?
    ) {
        self.isObserving = isObserving
        self.lastSyncFinishedAt = lastSyncFinishedAt
        self.lastSyncSampleCount = lastSyncSampleCount
        self.lastSyncDeletedCount = lastSyncDeletedCount
        self.authorizationRequested = authorizationRequested
        self.lastErrorMessage = lastErrorMessage
    }

    public static let idle = HealthKitIngestStatus(
        isObserving: false,
        lastSyncFinishedAt: nil,
        lastSyncSampleCount: 0,
        lastSyncDeletedCount: 0,
        authorizationRequested: false,
        lastErrorMessage: nil
    )
}

public enum HealthKitConnectionState: String, Sendable {
    case connected = "Connected"
    case permissionNeeded = "Permission needed"
    case notConnected = "Not connected"
}

public extension HealthKitIngestStatus {
    var connectionState: HealthKitConnectionState {
        if authorizationRequested || lastSyncFinishedAt != nil {
            return .connected
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return .notConnected
        }
        return .permissionNeeded
    }
}

public struct HealthKitIngestOutcome: Sendable, Equatable {
    public let samplesIngested: Int
    public let samplesDeleted: Int
    public let affectedFamilies: Set<HealthKitMetricFamily>

    public init(
        samplesIngested: Int,
        samplesDeleted: Int,
        affectedFamilies: Set<HealthKitMetricFamily>
    ) {
        self.samplesIngested = samplesIngested
        self.samplesDeleted = samplesDeleted
        self.affectedFamilies = affectedFamilies
    }

    public static let empty = HealthKitIngestOutcome(
        samplesIngested: 0,
        samplesDeleted: 0,
        affectedFamilies: []
    )
}

public struct HealthKitMetricSnapshot: Sendable, Equatable {
    public let family: HealthKitMetricFamily
    public let capturedAt: Date
    public let status: HealthKitIngestStatus

    public init(family: HealthKitMetricFamily, capturedAt: Date, status: HealthKitIngestStatus) {
        self.family = family
        self.capturedAt = capturedAt
        self.status = status
    }
}
