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
    private var refreshTask: Task<Void, Never>?

    init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func refresh() async {
        refreshTask?.cancel()
        isLoading = true
        errorMessage = nil

        let store = self.store
        let calendar = self.calendar
        let cutoff = self.cutoff
        let task = Task(priority: .userInitiated) { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeBoard(store: store, calendar: calendar, cutoff: cutoff)
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case let .success(model):
                self.model = model
                self.errorMessage = nil
            case let .failure(message):
                self.model = MuscleVolumeBoardModel(rows: [])
                self.errorMessage = message
            }
            self.isLoading = false
        }
        refreshTask = task
        await task.value
    }

    private enum BoardResult: Sendable {
        case success(MuscleVolumeBoardModel)
        case failure(String)
    }

    private nonisolated static func computeBoard(
        store: PersistenceStore,
        calendar: Calendar,
        cutoff: DayCutoff
    ) -> BoardResult {
        do {
            let today = HelmDay.day(for: .now, cutoff: cutoff, calendar: calendar)
            let model = try TrendsDataBuilder.buildMuscleVolumeBoard(
                store: store,
                weekContaining: today,
                calendar: calendar,
                cutoff: cutoff
            )
            return .success(model)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

enum MuscleVolumeBootstrap {
    @MainActor
    static let store = MuscleVolumeBoardStore(store: PersistenceBootstrap.persistenceStore)
}
