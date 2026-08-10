import CoachLLM
import Core
import HealthKitIngest

enum MethodologyBootstrap {
    nonisolated(unsafe) private(set) static var document: MethodologyDocument = .empty

    static func start() {
        let loaded = (try? MethodologyLibrary.bundled()) ?? .empty
        document = loaded
        MethodologyEvidenceSupport.configure(with: loaded)
        ResourceModuleIndex.configure(with: loaded)
    }
}
