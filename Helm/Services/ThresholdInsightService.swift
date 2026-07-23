import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Observation
import Persistence
import ReadinessKit

@MainActor
@Observable
final class ThresholdInsightService {
    private(set) var currentInsight: ThresholdInsight?

    private let persistence: PersistenceStore
    private let store: ThresholdInsightStore
    private let jsonDecoder = JSONDecoder()

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        store = ThresholdInsightStore(metadata: persistence.appMetadata)
    }

    func refresh(today: ReadinessScore?, calendar: Calendar = .current) async {
        guard let today else {
            currentInsight = nil
            return
        }

        let day = HelmDay.day(for: .now, calendar: calendar)
        let yesterday = day.adding(days: -1, calendar: calendar)
        guard let previous = try? loadScore(for: yesterday),
              let insight = ThresholdInsightEngine.detect(previous: previous, current: today) else {
            currentInsight = nil
            return
        }

        do {
            guard try store.shouldSurface(insight, on: day) else {
                currentInsight = nil
                return
            }
            currentInsight = insight
            try store.markSurfaced(insight, on: day)
            if HelmThemeCoordinator.shared.thresholdInsightHapticsEnabled {
                HapticEngine.shared.play(.thresholdInsight)
            }
        } catch {
            currentInsight = nil
        }
    }

    private func loadScore(for day: HelmDay) throws -> ReadinessScore? {
        guard let json = try persistence.readiness.fetchScoreJSON(helmDay: day) else {
            return nil
        }
        guard let data = json.data(using: .utf8) else { return nil }
        return try jsonDecoder.decode(ReadinessScore.self, from: data)
    }
}
