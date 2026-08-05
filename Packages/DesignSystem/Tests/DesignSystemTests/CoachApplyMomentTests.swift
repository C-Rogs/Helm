import Testing
@testable import DesignSystem

@Suite("Coach apply moment")
struct CoachApplyMomentTests {
    @Test("coachAdjust pattern builds for full and low power")
    func coachAdjustPatternBuilds() throws {
        _ = try HapticPatternBuilder.pattern(for: .coachAdjust, lowPowerMode: false)
        _ = try HapticPatternBuilder.pattern(for: .coachAdjust, lowPowerMode: true)
    }

    @Test("coachAdjust fallback is success notification")
    func coachAdjustFallback() {
        switch HapticFallbackResolver.fallback(for: .coachAdjust) {
        case .notification(.success):
            break
        default:
            Issue.record("Expected notification success fallback for coachAdjust")
        }
    }
}
