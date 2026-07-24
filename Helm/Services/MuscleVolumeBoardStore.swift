import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Observation
import Persistence

@Observable
@MainActor
final class MuscleVolumeBoardStore {
    private(set) var model: MuscleVolumeBoardModel?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff

    init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func refresh() {
        isLoading = true
        errorMessage = nil

        do {
            let today = HelmDay.day(for: .now, cutoff: cutoff, calendar: calendar)
            model = try TrendsDataBuilder.buildMuscleVolumeBoard(
                store: store,
                weekContaining: today,
                calendar: calendar,
                cutoff: cutoff
            )
        } catch {
            model = MuscleVolumeBoardModel(rows: [])
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

enum MuscleVolumeBootstrap {
    @MainActor
    static let store = MuscleVolumeBoardStore(store: PersistenceBootstrap.persistenceStore)
}
