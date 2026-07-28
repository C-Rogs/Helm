import HealthKitIngest
import Persistence

enum CoachArchetypeBootstrap {
    static func start() {
        let loaded = (try? CoachArchetypeLibrary.bundled()) ?? .empty
        CoachArchetypeSupport.configure(with: loaded)
    }
}
