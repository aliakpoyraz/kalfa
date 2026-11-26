import XCTest
@testable import KalfaUI

final class BrightnessScaleTests: XCTestCase {

    private let floors: [Double] = [0.4, 0.3, 0.2]

    // MARK: The floor

    /// The promise the feature rests on: no level, on any kind of display, lets
    /// through less than the floor. A screen that can be dragged to black is a
    /// screen the user cannot find the slider on to drag it back.
    func testNothingGoesUnderTheFloor() {
        for floor in floors {
            for softwareOnly in [false, true] {
                for level in stride(from: -200.0, through: 200.0, by: 0.5) {
                    let factor = BrightnessScale.factor(level: level, floor: floor, softwareOnly: softwareOnly)
                    XCTAssertGreaterThanOrEqual(factor, floor - 1e-9, "level \(level), floor \(floor)")
                    XCTAssertLessThanOrEqual(factor, 1 + 1e-9, "level \(level), floor \(floor)")
                }
            }
        }
    }

    func testBacklightRangeLeavesThePictureAlone() {
        for level in stride(from: 0.0, through: 100.0, by: 1) {
            XCTAssertEqual(BrightnessScale.factor(level: level, floor: 0.3, softwareOnly: false), 1)
        }
    }

    func testBottomOfTheScaleIsExactlyTheFloor() {
        for floor in floors {
            let factor = BrightnessScale.factor(level: BrightnessScale.lowest, floor: floor, softwareOnly: false)
            XCTAssertEqual(factor, floor, accuracy: 1e-9)
        }
    }

    func testDarkeningIsMonotonic() {
        var previous = 0.0
        for level in stride(from: BrightnessScale.lowest, through: 0, by: 1) {
            let factor = BrightnessScale.factor(level: level, floor: 0.2, softwareOnly: false)
            XCTAssertGreaterThanOrEqual(factor, previous)
            previous = factor
        }
    }

    func testSoftwareOnlyDisplayUsesItsWholeRange() {
        XCTAssertEqual(BrightnessScale.factor(level: 100, floor: 0.3, softwareOnly: true), 1, accuracy: 1e-9)
        XCTAssertEqual(BrightnessScale.factor(level: 0, floor: 0.3, softwareOnly: true), 0.3, accuracy: 1e-9)
        XCTAssertEqual(BrightnessScale.factor(level: 50, floor: 0.3, softwareOnly: true), 0.65, accuracy: 1e-9)
    }

    // MARK: Backlight mapping

    /// Zero on the scale must not be zero on the built-in backlight: that
    /// switches the panel off.
    func testBuiltInBacklightNeverReachesZero() {
        let minimum = 1.0 / 64.0
        XCTAssertEqual(BrightnessScale.raw(fromPercent: 0, minimum: minimum), minimum, accuracy: 1e-12)
        XCTAssertGreaterThan(BrightnessScale.raw(fromPercent: -40, minimum: minimum), 0)
        XCTAssertEqual(BrightnessScale.raw(fromPercent: 100, minimum: minimum), 1, accuracy: 1e-12)
    }

    func testBacklightMappingRoundTrips() {
        for minimum in [0.0, 1.0 / 64.0] {
            for percent in stride(from: 0.0, through: 100.0, by: 6.25) {
                let raw = BrightnessScale.raw(fromPercent: percent, minimum: minimum)
                XCTAssertEqual(BrightnessScale.percent(fromRaw: raw, minimum: minimum), percent, accuracy: 1e-9)
            }
        }
    }

    func testBacklightBelowTheMinimumReadsAsZero() {
        XCTAssertEqual(BrightnessScale.percent(fromRaw: 0, minimum: 1.0 / 64.0), 0)
    }

    // MARK: Coming back

    func testSavedDarkeningReturnsWhileBacklightIsAtTheBottom() {
        XCTAssertEqual(BrightnessScale.restored(hardware: 0, savedDim: -30, allowsBelowZero: true), -30)
        XCTAssertEqual(BrightnessScale.restored(hardware: 1, savedDim: -30, allowsBelowZero: true), -30)
    }

    /// Raised with the keyboard while Kalfa was closed: the darkening must not
    /// come back on top of it.
    func testSavedDarkeningIsDroppedOnceBacklightWasRaised() {
        XCTAssertEqual(BrightnessScale.restored(hardware: 40, savedDim: -30, allowsBelowZero: true), 40)
    }

    func testSavedDarkeningIsIgnoredWhenTheFeatureIsOff() {
        XCTAssertEqual(BrightnessScale.restored(hardware: 0, savedDim: -30, allowsBelowZero: false), 0)
    }

    func testSavedDarkeningIsHeldToTheScale() {
        XCTAssertEqual(BrightnessScale.restored(hardware: 0, savedDim: -400, allowsBelowZero: true), BrightnessScale.lowest)
        XCTAssertEqual(BrightnessScale.restored(hardware: 0, savedDim: nil, allowsBelowZero: true), 0)
    }
}
