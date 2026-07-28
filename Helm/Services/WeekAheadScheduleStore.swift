import Core
import DesignSystem
import Foundation
import Observation
import Persistence

@Observable
@MainActor
final class WeekAheadScheduleStore {
    private(set) var model: WeekAheadScheduleModel?
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
            model = try WeekAheadScheduleBuilder.build(
                store: store,
                today: today,
                calendar: calendar,
                cutoff: cutoff
            )
        } catch {
            model = WeekAheadScheduleModel(rows: [])
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

enum WeekAheadScheduleBootstrap {
    @MainActor
    static let store = WeekAheadScheduleStore(store: PersistenceBootstrap.persistenceStore)
}
