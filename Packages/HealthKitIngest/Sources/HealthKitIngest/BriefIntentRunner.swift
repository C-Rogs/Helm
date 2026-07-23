import Core
import Diagnostics
import Foundation
import OSLog
import Persistence
import ReadinessKit

public enum BriefIntentOutcome: Sendable, Equatable {
    case lockedPhone
    case succeeded(notificationPosted: Bool)
    case timedOut
    case failed(String)
}

public actor BriefIntentRunner {
    public static let maxRuntimeSeconds: TimeInterval = 25

    private let ingest: HealthKitIngest
    private let readinessEngine: ReadinessEngine
    private let prescriptionEngine: PlanPrescriptionEngine
    private let briefEngine: BriefEngine
    private let missStore: BriefIntentMissStore
    private let protectedData: any ProtectedDataChecking
    private let notificationPoster: any BriefNotificationPosting
    private let diagnosticsLog: DiagnosticsLog
    private let signpost: HelmSignpost
    private let log: Logger
    private let calendar: Calendar
    private let cutoff: DayCutoff

    public init(
        ingest: HealthKitIngest,
        readinessEngine: ReadinessEngine,
        prescriptionEngine: PlanPrescriptionEngine,
        briefEngine: BriefEngine,
        missStore: BriefIntentMissStore,
        protectedData: any ProtectedDataChecking = LiveProtectedDataChecker(),
        notificationPoster: any BriefNotificationPosting = NoOpBriefNotificationPoster(),
        diagnosticsLog: DiagnosticsLog = .shared,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.ingest = ingest
        self.readinessEngine = readinessEngine
        self.prescriptionEngine = prescriptionEngine
        self.briefEngine = briefEngine
        self.missStore = missStore
        self.protectedData = protectedData
        self.notificationPoster = notificationPoster
        self.diagnosticsLog = diagnosticsLog
        self.calendar = calendar
        self.cutoff = cutoff
        signpost = HelmSignpost(name: .briefIntentRun, category: .appIntents)
        log = helmLogger(category: .appIntents)
    }

    public func run(now: Date = .now, attemptNarration: Bool = true) async -> BriefIntentOutcome {
        let invocationID = UUID().uuidString
        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)

        let day = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)

        await diagnosticsLog.record(
            category: .appIntents,
            level: .info,
            message: "Brief intent started",
            context: [
                "invocationID": invocationID,
                "helmDay": day.formatted
            ]
        )

        defer {
            signpost.end(id: signpostID)
        }

        guard protectedData.isProtectedDataAvailable else {
            log.info("Brief intent skipped: protected data unavailable invocation=\(invocationID, privacy: .public)")
            do {
                try missStore.recordMiss(for: day)
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .appIntents,
                    message: "Failed to record brief intent miss",
                    context: ["invocationID": invocationID]
                )
            }

            await diagnosticsLog.record(
                category: .appIntents,
                level: .info,
                message: "Brief intent deferred: phone locked",
                context: [
                    "invocationID": invocationID,
                    "helmDay": day.formatted
                ]
            )
            return .lockedPhone
        }

        let outcome = await runBoundedPipeline(
            day: day,
            now: now,
            attemptNarration: attemptNarration,
            invocationID: invocationID
        )

        await diagnosticsLog.record(
            category: .appIntents,
            level: .info,
            message: "Brief intent finished",
            context: [
                "invocationID": invocationID,
                "outcome": String(describing: outcome)
            ]
        )

        return outcome
    }

    private func runBoundedPipeline(
        day: HelmDay,
        now: Date,
        attemptNarration: Bool,
        invocationID: String
    ) async -> BriefIntentOutcome {
        await withTaskGroup(of: BriefIntentOutcome?.self) { group in
            group.addTask {
                await self.executePipeline(
                    day: day,
                    attemptNarration: attemptNarration,
                    invocationID: invocationID
                )
            }

            group.addTask {
                let nanoseconds = UInt64(Self.maxRuntimeSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                return BriefIntentOutcome.timedOut
            }

            let first = await group.next() ?? .failed("Brief intent produced no result")
            group.cancelAll()
            return first ?? .failed("Brief intent produced no result")
        }
    }

    private func executePipeline(
        day: HelmDay,
        attemptNarration: Bool,
        invocationID: String
    ) async -> BriefIntentOutcome {
        do {
            let ingestOutcome = await ingest.syncNow()
            log.info(
                "Brief intent harvested samples=\(ingestOutcome.samplesIngested, privacy: .public) invocation=\(invocationID, privacy: .public)"
            )

            let readiness = try await readinessEngine.recompute(for: day)
            let prescriptionState = try await prescriptionEngine.dashboardState(
                for: day,
                readiness: readiness
            )
            let prescriptionSummary: PrescribedSessionSummary?
            if case let .prescribed(summary) = prescriptionState {
                prescriptionSummary = summary
            } else {
                prescriptionSummary = nil
            }

            let brief = try await briefEngine.ensureBrief(
                for: day,
                readiness: readiness,
                prescriptionSummary: prescriptionSummary,
                attemptNarration: attemptNarration
            )

            try missStore.clearMiss(for: day)

            let notificationPosted = await notificationPoster.postMorningBrief(brief)
            log.info(
                "Brief intent notificationPosted=\(notificationPosted, privacy: .public) invocation=\(invocationID, privacy: .public)"
            )

            return .succeeded(notificationPosted: notificationPosted)
        } catch {
            if Task.isCancelled {
                return .timedOut
            }

            await diagnosticsLog.capture(
                error: error,
                category: .appIntents,
                message: "Brief intent pipeline failed",
                context: ["invocationID": invocationID]
            )
            return .failed(error.localizedDescription)
        }
    }
}
