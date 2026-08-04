import DesignSystem
import XCTest

final class HelmRPEWheelValuesTests: XCTestCase {
    func testAllValuesSpanFiveToTenByHalfStep() {
        let values = HelmRPEWheelValues.allValues
        XCTAssertEqual(values.count, 11)
        XCTAssertEqual(values.first, 5.0)
        XCTAssertEqual(values.last, 10.0)
        XCTAssertEqual(values, [5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0])
    }

    func testSnappedClampsAndRoundsToNearestHalf() {
        XCTAssertEqual(HelmRPEWheelValues.snapped(4.2), 5.0)
        XCTAssertEqual(HelmRPEWheelValues.snapped(7.24), 7.0)
        XCTAssertEqual(HelmRPEWheelValues.snapped(7.26), 7.5)
        XCTAssertEqual(HelmRPEWheelValues.snapped(10.8), 10.0)
    }

    func testFormattedOmitsTrailingZeroForWholeNumbers() {
        XCTAssertEqual(HelmRPEWheelValues.formatted(8.0), "8")
        XCTAssertEqual(HelmRPEWheelValues.formatted(8.5), "8.5")
    }
}
