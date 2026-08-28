import Testing
@testable import DesignSystem

@Suite("Calorie arc model")
struct CalorieArcModelTests {
    @Test("eat-to is the scale end when there is no visualized active")
    func eatToAtEndWithoutActive() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .none)
        #expect(model.ceilingKcal == 2_400)
        #expect(model.eatToFraction == 1)
        #expect(model.visualizedActiveKcal == 0)
        #expect(model.bands.map(\.kind) == [.baseline])
        #expect(model.remainingKcal == 600)
        #expect(model.centerCaption == "LEFT")
        #expect(model.legend.map(\.label) == ["IN"])
    }

    @Test("fresh active extends the scale past eat-to")
    func freshActiveExtendsScale() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
        #expect(model.ceilingKcal == 2_820)
        #expect(model.eatToFraction < 1)
        #expect(abs(model.eatToFraction - 2_400.0 / 2_820.0) < 0.0001)
        #expect(model.visualizedActiveKcal == 420)
        #expect(model.showsActiveBand)
        #expect(model.bands.map(\.kind) == [.baseline, .active])
        #expect(model.remainingKcal == 600)
        #expect(model.legend.map(\.label) == ["ACTIVE", "IN"])
    }

    @Test("remaining stays vs eat-to even when active is on the scale")
    func remainingIgnoresActive() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 2_650, active: .fresh(420))
        #expect(model.remainingKcal == -250)
        #expect(model.isOver)
        #expect(model.centerCaption == "OVER")
        #expect(model.ceilingKcal == 2_820)
        let fills = model.fills(drawProgress: 1)
        #expect(fills.map(\.kind) == [.intake, .over])
        #expect(fills.last?.end ?? 0 < 1)
    }

    @Test("logged past allowance stretches the ceiling")
    func overPastActiveStretchesCeiling() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 3_100, active: .fresh(420))
        #expect(model.ceilingKcal == 3_100)
        #expect(model.loggedFraction == 1)
        #expect(model.eatToFraction < model.activeEndFraction)
        #expect(model.activeEndFraction < 1)
    }

    @Test("stale and tiny active stay off the scale")
    func untrustedActiveStaysOffScale() {
        let syncing = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 900, active: .syncing)
        #expect(syncing.visualizedActiveKcal == 0)
        #expect(syncing.ceilingKcal == 2_400)
        #expect(syncing.legend.contains { $0.label == "ACTIVE" && $0.value == "SYNC" })

        let partial = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 900, active: .partial(35))
        #expect(partial.visualizedActiveKcal == 0)
        #expect(partial.legend.contains { $0.id == "active" && $0.value == "35" })

        let tiny = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 900, active: .fresh(40))
        #expect(tiny.visualizedActiveKcal == 0)
        #expect(tiny.ceilingKcal == 2_400)
        #expect(tiny.legend.contains { $0.label == "ACTIVE" && $0.value == "40" })
    }

    @Test("modest fresh active opens the band")
    func modestActiveOpensBand() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 900, active: .fresh(100))
        #expect(model.visualizedActiveKcal == 100)
        #expect(model.showsActiveBand)
    }

    @Test("eat-to docks to the gap when it is the scale end")
    func eatToDocksToGapEnd() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_200, active: .none)
        let eatTo = model.targetLabel
        #expect(eatTo?.anchor == .gapEnd)
        #expect(eatTo?.value == "2400")
        #expect(eatTo?.caption == "EAT-TO")
        #expect(model.attachedLabels.contains { $0.role == .origin && $0.value == "0" })
    }

    @Test("eat-to sits on the ring when active extends the scale")
    func eatToRadialWhenActive() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_200, active: .fresh(420))
        let eatTo = model.targetLabel
        #expect(eatTo?.anchor == .radial)
        #expect(eatTo?.value == "2.4k")
        #expect(model.attachedLabels.contains { $0.role == .origin })
        #expect(model.attachedLabels.contains { $0.role == .scaleEnd })
    }

    @Test("progress label drops when it collides with eat-to")
    func progressYieldsToEatTo() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 2_650, active: .fresh(420))
        #expect(model.targetLabel != nil)
        #expect(model.attachedLabels.contains { $0.role == .progress } == false)
    }

    @Test("accessibility hides radial labels and falls back in the hole")
    func accessibilityHidesRadial() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_200, active: .fresh(420))
        #expect(model.targetLabel?.anchor == .radial)
        #expect(model.showsHoleEatTo(isAccessibilitySize: true))
        #expect(model.showsHoleEatTo(isAccessibilitySize: false) == false)
        let visible = model.visibleAttachedLabels(isAccessibilitySize: true)
        #expect(visible.allSatisfy { $0.anchor != .radial })
    }

    @Test("compact kcal shortens tick labels")
    func compactKcal() {
        #expect(CalorieArcModel.compactKcal(250) == "250")
        #expect(CalorieArcModel.compactKcal(2_000) == "2k")
        #expect(CalorieArcModel.compactKcal(2_400) == "2.4k")
        #expect(CalorieArcModel.compactKcal(12_000) == "12k")
    }

    @Test("minor ticks skip majors")
    func minorTicksAvoidMajors() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
        let majors = model.ticks.filter { $0.kind.isMajor }.map(\.fraction)
        for tick in model.ticks where tick.kind == .minor {
            for major in majors {
                #expect(abs(tick.fraction - major) >= CalorieArcMetrics.tickCollisionFraction)
            }
        }
    }

    @Test("empty log uses a dash in the IN chip")
    func emptyLogLegend() {
        let model = CalorieArcModel(eatToKcal: 2_200, loggedKcal: nil, active: .none)
        #expect(model.hasLogged == false)
        #expect(model.loggedKcal == 0)
        #expect(model.remainingKcal == 2_200)
        #expect(model.legend.first { $0.id == "in" }?.value == "-")
        #expect(model.fills(drawProgress: 1).isEmpty)
        #expect(model.attachedLabels.contains { $0.role == .target })
        #expect(model.attachedLabels.contains { $0.role == .progress } == false)
    }

    @Test("fill splits at eat-to when over")
    func fillSplitsAtEatTo() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 2_650, active: .fresh(420))
        #expect(model.fills(drawProgress: 0).isEmpty)

        let half = model.fills(drawProgress: 0.5)
        #expect(half.count == 1)
        #expect(half[0].kind == .intake)

        let full = model.fills(drawProgress: 1)
        #expect(full.map(\.kind) == [.intake, .over])
        #expect(abs(full[0].end - model.eatToFraction) < 0.0001)
        #expect(abs(full[1].start - model.eatToFraction) < 0.0001)
    }

    @Test("accessibility names eat-to as the target")
    func accessibilityMentionsEatTo() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
        #expect(model.accessibilityLabel.contains("Eat-to 2400"))
        #expect(model.accessibilityLabel.contains("1800 logged"))
        #expect(model.accessibilityLabel.contains("not in eat-to"))
    }

    @Test("gap labels keep full digits")
    func gapLabelsUseFullDigits() {
        let model = CalorieArcModel(eatToKcal: 2_400, loggedKcal: nil, active: .none)
        #expect(model.attachedLabels.first { $0.role == .origin }?.value == "0")
        #expect(model.targetLabel?.value == "2400")
    }

    @Test("label docks match gap and radial seats")
    func labelDocks() {
        #expect(CalorieArcLabelDock.resolve(anchor: .gapStart, fraction: 0) == .gapStart)
        #expect(CalorieArcLabelDock.resolve(anchor: .gapEnd, fraction: 1) == .gapEnd)
        #expect(CalorieArcLabelDock.resolve(anchor: .radial, fraction: 0.5) == .top)
        #expect(CalorieArcLabelDock.resolve(anchor: .radial, fraction: 0.15) == .left)
        #expect(CalorieArcLabelDock.resolve(anchor: .radial, fraction: 0.9) == .right)
    }
}
