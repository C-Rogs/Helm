import Foundation
import Testing
@testable import Core

@Suite("RemoteCompleteSetPolicy")
struct RemoteCompleteSetPolicyTests {
    @Test("incomplete and skipped sets apply; completed does not")
    func shouldApplyByStatus() {
        #expect(RemoteCompleteSetPolicy.shouldApply(status: .planned))
        #expect(RemoteCompleteSetPolicy.shouldApply(status: .skipped))
        #expect(!RemoteCompleteSetPolicy.shouldApply(status: .completed))
    }
}
