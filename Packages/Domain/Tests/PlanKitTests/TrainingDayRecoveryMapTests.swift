import Foundation
import Testing
@testable import PlanKit

@Suite("Training day recovery map")
struct TrainingDayRecoveryMapTests {
    @Test("arms defers push and pull")
    func armsDefersPush() {
        let kinds = TrainingDayRecoveryMap.conflictingKinds(forRegion: "arms")
        #expect(kinds.contains(.push))
        #expect(kinds.contains(.pull))
        #expect(kinds.contains(.arms))
    }

    @Test("sore arms phrase still maps to push+pull")
    func soreArmsPhrase() {
        let kinds = TrainingDayRecoveryMap.conflictingKinds(forRegion: "sore arms")
        #expect(kinds.contains(.push))
        #expect(kinds.contains(.pull))
    }

    @Test("tight hamstrings maps to legs")
    func tightHamstrings() {
        let kinds = TrainingDayRecoveryMap.conflictingKinds(forRegion: "tight hamstrings")
        #expect(kinds.contains(.legs))
    }

    @Test("preferred kind after push+pull defer is legs")
    func preferredIsLegs() {
        let preferred = TrainingDayRecoveryMap.preferredKind(
            rotation: [.push, .pull, .legs],
            deferred: [.push, .pull],
            consumed: []
        )
        #expect(preferred == .legs)
    }
}
