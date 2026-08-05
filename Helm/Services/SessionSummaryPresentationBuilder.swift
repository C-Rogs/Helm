import Core
import Foundation
import HealthKitIngest
import Persistence

/// Shared assembly for the end-of-workout summary and past-workout history detail.
@MainActor
enum SessionSummaryPresentationBuilder {
    /// Cheap, synchronous: stats + weekly landmarks, no timeline.
    static func base(
        session: WorkoutSessionDraft,
        store: PersistenceStore
    ) -> WorkoutFinishSummary? {
        try? WorkoutFinishSummaryAssembler.build(session: session, store: store)
    }

    /// Adds set/exercise/music markers + HealthKit heart-rate series.
    static func withTimeline(
        _ base: WorkoutFinishSummary,
        session: WorkoutSessionDraft,
        store: PersistenceStore,
        liveHeartRateFallback: [SessionHeartRateSample] = []
    ) async -> WorkoutFinishSummary {
        let markers = SessionSetMarkerBuilder.markers(
            from: session,
            startedAt: session.startedAt
        )
        let exerciseIDs = session.exercises.map(\.exerciseID)
        let displayNames = (try? store.exercises.displayNames(for: exerciseIDs)) ?? [:]
        let exerciseMarkers = SessionExerciseMarkerBuilder.markers(
            from: session,
            startedAt: session.startedAt,
            displayNames: displayNames
        )
        let musicSamples = (try? store.workoutMusicSamples.list(sessionID: session.id)) ?? []
        let endedAt = session.endedAt ?? Date()
        let capturedSegments = SessionMusicSegmentBuilder.build(
            samples: musicSamples,
            startedAt: session.startedAt,
            endedAt: endedAt
        )
        let musicSegments = await SongTempoLookupService.shared.fill(segments: capturedSegments)
        let heartRateSamples = await WorkoutHeartRateSeriesFetcher()
            .timelineSamplesForFinishChart(
                startedAt: session.startedAt,
                endedAt: endedAt,
                liveFallback: liveHeartRateFallback
            )
        return base.withSessionTimeline(
            samples: heartRateSamples,
            setMarkers: markers,
            exerciseMarkers: exerciseMarkers,
            musicSegments: musicSegments
        )
    }

    /// Full summary for a completed session (history browse path).
    static func build(
        session: WorkoutSessionDraft,
        store: PersistenceStore,
        liveHeartRateFallback: [SessionHeartRateSample] = []
    ) async -> WorkoutFinishSummary? {
        guard let base = base(session: session, store: store) else { return nil }
        return await withTimeline(
            base,
            session: session,
            store: store,
            liveHeartRateFallback: liveHeartRateFallback
        )
    }
}
