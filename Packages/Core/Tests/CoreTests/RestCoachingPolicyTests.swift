import Foundation
import Testing
@testable import Core

@Suite("Rest coaching policy")
struct RestCoachingPolicyTests {
    @Test("phases map remaining time")
    func phases() {
        #expect(RestCoachingPolicy.phase(remainingSeconds: 90, totalSeconds: 90) == .start)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 70, totalSeconds: 90) == .start)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 40, totalSeconds: 90) == .mid)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 10, totalSeconds: 90) == .windDown)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 3, totalSeconds: 90) == .windDown)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 0, totalSeconds: 90) == .expired)
    }

    @Test("short rest still reaches mid before wind-down")
    func shortRest() {
        #expect(RestCoachingPolicy.phase(remainingSeconds: 30, totalSeconds: 30) == .start)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 20, totalSeconds: 30) == .mid)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 10, totalSeconds: 30) == .windDown)

        // 15s prescription rest: wind-down scales to 5s so mid exists.
        #expect(RestCoachingPolicy.phase(remainingSeconds: 15, totalSeconds: 15) == .start)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 7, totalSeconds: 15) == .mid)
        #expect(RestCoachingPolicy.phase(remainingSeconds: 5, totalSeconds: 15) == .windDown)
    }

    @Test("lines stay terse and use up next")
    func lines() {
        #expect(
            RestCoachingPolicy.line(phase: .start, upNextName: "Cable Fly")
                == "Recover. Up next · Cable Fly."
        )
        #expect(RestCoachingPolicy.line(phase: .mid) == "Stay loose. Breathe.")
        #expect(
            RestCoachingPolicy.line(phase: .mid, formCue: "Drive through your heels.")
                == "Drive through your heels."
        )
        #expect(
            RestCoachingPolicy.line(phase: .mid, formCue: String(repeating: "a", count: 80))
                == "Stay loose. Breathe."
        )
        #expect(
            RestCoachingPolicy.line(phase: .windDown, upNextName: "Squat")
                == "Almost. Get set for Squat."
        )
        #expect(
            RestCoachingPolicy.line(phase: .expired, upNextName: "RDL")
                == "Rest done. Go · RDL."
        )
        #expect(RestCoachingPolicy.line(phase: .expired) == "Rest done. Hit the next set.")
    }
}
