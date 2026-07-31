import Foundation
import Testing

@Suite("Live Activity set progress")
struct LiveActivitySetProgressTests {
    @Test("current set is first incomplete")
    func firstIncomplete() {
        let statuses = [true, true, false, false]
        let number = statuses.firstIndex(where: { !$0 }).map { $0 + 1 }
        #expect(number == 3)
        #expect(statuses.count == 4)
    }

    @Test("all complete falls back to nil current")
    func allComplete() {
        let statuses = [true, true, true]
        let number = statuses.firstIndex(where: { !$0 }).map { $0 + 1 }
        #expect(number == nil)
    }
}
