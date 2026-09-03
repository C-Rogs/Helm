import Testing
@testable import HealthKitIngest

@Suite("Session swap phrase")
struct SessionSwapPhraseTests {
    @Test("compound swap does not swallow the move clause")
    func swapStopsBeforeMove() {
        let parsed = SessionSwapPhrase.parse(
            "replace leg press with leg extension and move it to the start"
        )
        #expect(parsed?.from.lowercased() == "leg press")
        #expect(parsed?.to.lowercased() == "leg extension")
        let move = SessionSwapPhrase.parseMove(
            "replace leg press with leg extension and move it to the start"
        )
        #expect(move?.target == nil)
        #expect(move?.position == .start)

        let putFirst = SessionSwapPhrase.parseMove("put it first")
        #expect(putFirst?.target == nil)
        #expect(putFirst?.position == .start)

        let atStart = SessionSwapPhrase.parseMove("put that at the start")
        #expect(atStart?.target == nil)
        #expect(atStart?.position == .start)

        let namedEnd = SessionSwapPhrase.parseMove("move the romanian deadlift to the end")
        #expect(namedEnd?.target?.lowercased().contains("romanian") == true)
        #expect(namedEnd?.position == .end)
    }

    @Test("messy swap phrasing still splits from and to")
    func messySwapPhrasing() {
        let swapOut = SessionSwapPhrase.parse("swap out the leg press for leg extension")
        #expect(swapOut?.from.lowercased() == "leg press")
        #expect(swapOut?.to.lowercased() == "leg extension")

        let canWe = SessionSwapPhrase.parse("can we do hammer curls instead of face pull")
        #expect(canWe?.from.lowercased().contains("face pull") == true)
        #expect(canWe?.to.lowercased().contains("hammer") == true)

        let insteadDo = SessionSwapPhrase.parse(
            "instead of the leg press, do leg extension and move it to the start"
        )
        #expect(insteadDo?.from.lowercased() == "leg press")
        #expect(insteadDo?.to.lowercased() == "leg extension")

        let ropeForDB = SessionSwapPhrase.parse(
            "Replace hammer curls rope attachment for hammer curls dumbbell"
        )
        #expect(ropeForDB?.from.lowercased().contains("rope") == true)
        #expect(ropeForDB?.to.lowercased().contains("dumbbell") == true)
    }

    @Test("instead-of and add phrases")
    func insteadOfAndAdd() {
        let parsed = SessionSwapPhrase.parse("hammer curls instead of face pull")
        #expect(parsed?.from.lowercased().contains("face pull") == true)
        #expect(parsed?.to.lowercased().contains("hammer") == true)
        #expect(SessionSwapPhrase.parseAdd("add rope hammer curl") == "rope hammer curl")
        #expect(SessionSwapPhrase.parseAdd("include face pull please") == "face pull")
        #expect(
            SessionSwapPhrase.parseAddList("add dumbbell curls and leg extensions")
                == ["dumbbell curls", "leg extensions"]
        )
        #expect(
            SessionSwapPhrase.parseAddList("add face pull and move it to the start")
                == ["face pull"]
        )
        #expect(
            SessionSwapPhrase.parseAddList("include curls, extensions, and face pull")
                .map { $0.lowercased() }
                == ["curls", "extensions", "face pull"]
        )
        #expect(SessionSwapPhrase.parseAdd("Add in crunch machine at 32kg") == "crunch machine")
        #expect(SessionSwapPhrase.parseNamedLoadKg("Add in crunch machine at 32kg") == 32)
        #expect(
            SessionSwapPhrase.parseAdd("I want to add another exercise. Crunch machine")?
                .lowercased()
                .contains("crunch") == true
        )
        #expect(SessionSwapPhrase.parseAddList("No add new exercise").isEmpty)
    }

    @Test("expand order simulates swap then move to start")
    func expandOrderSwapThenStart() {
        let ordered = SessionSwapPhrase.expandOrder(
            sessionOrder: ["leg-press", "rdl", "curl"],
            replacing: "leg-press",
            with: "leg-extension",
            moving: "leg-extension",
            to: .start
        )
        #expect(ordered == ["leg-extension", "rdl", "curl"])
    }
}
