import DesignSystem
import XCTest

final class HelmDurationWheelValuesTests: XCTestCase {
    func testAllValuesSpanFifteenToTenMinutesByFiveSeconds() {
        let values = HelmDurationWheelValues.allValues
        XCTAssertEqual(values.first, 15)
        XCTAssertEqual(values.last, 600)
        XCTAssertEqual(values.count, ((600 - 15) / 5) + 1)
        XCTAssertTrue(values.allSatisfy { ($0 - 15).isMultiple(of: 5) })
    }

    func testPresetsAreIncluded() {
        for preset in HelmDurationWheelValues.presets {
            XCTAssertTrue(HelmDurationWheelValues.allValues.contains(preset))
            XCTAssertTrue(HelmDurationWheelValues.isPreset(preset))
        }
        XCTAssertFalse(HelmDurationWheelValues.isPreset(75))
    }

    func testSnappedClampsAndRoundsToNearestFive() {
        XCTAssertEqual(HelmDurationWheelValues.snapped(0), 15)
        XCTAssertEqual(HelmDurationWheelValues.snapped(17), 15)
        XCTAssertEqual(HelmDurationWheelValues.snapped(18), 20)
        XCTAssertEqual(HelmDurationWheelValues.snapped(92), 90)
        XCTAssertEqual(HelmDurationWheelValues.snapped(93), 95)
        XCTAssertEqual(HelmDurationWheelValues.snapped(999), 600)
    }

    func testFormattedUsesMmss() {
        XCTAssertEqual(HelmDurationWheelValues.formatted(0), "0:00")
        XCTAssertEqual(HelmDurationWheelValues.formatted(59), "0:59")
        XCTAssertEqual(HelmDurationWheelValues.formatted(90), "1:30")
        XCTAssertEqual(HelmDurationWheelValues.formatted(125), "2:05")
    }
}

final class RestTimerFormattingTests: XCTestCase {
    func testMmssClampsAndFormats() {
        XCTAssertEqual(RestTimerFormatting.mmss(-3), "0:00")
        XCTAssertEqual(RestTimerFormatting.mmss(0), "0:00")
        XCTAssertEqual(RestTimerFormatting.mmss(9), "0:09")
        XCTAssertEqual(RestTimerFormatting.mmss(60), "1:00")
        XCTAssertEqual(RestTimerFormatting.mmss(600), "10:00")
    }
}
