import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - CompassBarViewTests (LAR-50)
// Tests for the pure logic functions in CompassBarLogic.

final class CompassBarViewTests: XCTestCase {

    // MARK: - normalizedDiff

    func testNormalizedDiffZero() {
        XCTAssertEqual(CompassBarLogic.normalizedDiff(0), 0, accuracy: 1e-10)
    }

    func testNormalizedDiffPositive() {
        XCTAssertEqual(CompassBarLogic.normalizedDiff(45), 45, accuracy: 1e-10)
        XCTAssertEqual(CompassBarLogic.normalizedDiff(180), 180, accuracy: 1e-10)
    }

    func testNormalizedDiffNegative() {
        XCTAssertEqual(CompassBarLogic.normalizedDiff(-45), -45, accuracy: 1e-10)
        XCTAssertEqual(CompassBarLogic.normalizedDiff(-180), -180, accuracy: 1e-10)
    }

    func testNormalizedDiffWrapsOver180() {
        // 270° becomes -90° (shorter path going the other way)
        XCTAssertEqual(CompassBarLogic.normalizedDiff(270), -90, accuracy: 1e-10)
    }

    func testNormalizedDiffWrapsUnderNeg180() {
        // -270° becomes +90°
        XCTAssertEqual(CompassBarLogic.normalizedDiff(-270), 90, accuracy: 1e-10)
    }

    func testNormalizedDiffFullCircle() {
        XCTAssertEqual(CompassBarLogic.normalizedDiff(360), 0, accuracy: 1e-10)
        XCTAssertEqual(CompassBarLogic.normalizedDiff(-360), 0, accuracy: 1e-10)
    }

    func testNormalizedDiffBeyondFullCircle() {
        XCTAssertEqual(CompassBarLogic.normalizedDiff(540), 180, accuracy: 1e-10)
        XCTAssertEqual(CompassBarLogic.normalizedDiff(-540), -180, accuracy: 1e-10)
    }

    func testNormalizedDiffIsAlwaysInRange() {
        let inputs = stride(from: -720.0, through: 720.0, by: 37.0)
        for input in inputs {
            let result = CompassBarLogic.normalizedDiff(input)
            XCTAssertGreaterThanOrEqual(result, -180, "normalizedDiff(\(input)) = \(result) is < -180")
            XCTAssertLessThanOrEqual(result, 180, "normalizedDiff(\(input)) = \(result) is > 180")
        }
    }

    // MARK: - isOffScreen

    func testIsOffScreenReturnsFalseWhenInsideFoV() {
        // Directly ahead — on screen
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: 0, fovHalfAngle: 30))
        // Just inside
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: 29.9, fovHalfAngle: 30))
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: -29.9, fovHalfAngle: 30))
    }

    func testIsOffScreenReturnsTrueWhenOutsideFoV() {
        // Just beyond FoV edge
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: 30.1, fovHalfAngle: 30))
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: -30.1, fovHalfAngle: 30))
        // Well off screen
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: 90, fovHalfAngle: 30))
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: -90, fovHalfAngle: 30))
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: 180, fovHalfAngle: 30))
    }

    func testIsOffScreenAtExactBoundaryIsOnScreen() {
        // Exactly at the FoV edge is considered on screen (not strictly greater)
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: 30.0, fovHalfAngle: 30))
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: -30.0, fovHalfAngle: 30))
    }

    func testIsOffScreenUsesDefaultFoVHalfAngle() {
        // Default fovHalfAngle is 30°
        XCTAssertEqual(CompassBarView.fovHalfAngle, 30.0)
        XCTAssertFalse(CompassBarLogic.isOffScreen(angleDiff: 20))
        XCTAssertTrue(CompassBarLogic.isOffScreen(angleDiff: 45))
    }

    // MARK: - chevronSize

    func testChevronSizeAtZeroScore() {
        // Score of 0 → minimum size
        let size = CompassBarLogic.chevronSize(for: 0)
        XCTAssertEqual(size, 5.0, accuracy: 0.01)
    }

    func testChevronSizeAtIconicScore() {
        // Score of 10,000 (sqrt(10000/10000) = 1.0) → maximum size
        let size = CompassBarLogic.chevronSize(for: 10_000)
        XCTAssertEqual(size, 10.0, accuracy: 0.01)
    }

    func testChevronSizeBeyondIconicClamped() {
        // Scores above 10,000 should be clamped to maximum
        let size = CompassBarLogic.chevronSize(for: 100_000)
        XCTAssertEqual(size, 10.0, accuracy: 0.01)
    }

    func testChevronSizeAtRegularSignificance() {
        // Score of 2500 → sqrt(2500/10000) = 0.5 → 5 + 0.5*5 = 7.5
        let size = CompassBarLogic.chevronSize(for: 2_500)
        XCTAssertEqual(size, 7.5, accuracy: 0.01)
    }

    func testChevronSizeIsMonotonicallyIncreasing() {
        let scores = [0.0, 400, 1000, 2500, 5000, 8000, 10_000]
        var previous = -Double.infinity
        for score in scores {
            let size = CompassBarLogic.chevronSize(for: score)
            XCTAssertGreaterThanOrEqual(size, previous, "chevronSize not monotonically increasing at score \(score)")
            previous = size
        }
    }

    func testChevronSizeCustomRange() {
        // Custom min/max
        let size = CompassBarLogic.chevronSize(for: 0, min: 2, max: 8)
        XCTAssertEqual(size, 2.0, accuracy: 0.01)

        let sizeMax = CompassBarLogic.chevronSize(for: 10_000, min: 2, max: 8)
        XCTAssertEqual(sizeMax, 8.0, accuracy: 0.01)
    }

    // MARK: - xPosition

    func testXPositionCurrentHeadingIsAtCenter() {
        // A landmark exactly at the current heading should land on centerX
        let x = CompassBarLogic.xPosition(forDegree: 90, heading: 90, centerX: 200, ptsPerDegree: 4)
        XCTAssertEqual(x, 200, accuracy: 1e-10)
    }

    func testXPositionToTheRight() {
        // 10° to the right of heading → 10 * ptsPerDegree to the right of center
        let x = CompassBarLogic.xPosition(forDegree: 100, heading: 90, centerX: 200, ptsPerDegree: 4)
        XCTAssertEqual(x, 240, accuracy: 1e-10)
    }

    func testXPositionToTheLeft() {
        let x = CompassBarLogic.xPosition(forDegree: 80, heading: 90, centerX: 200, ptsPerDegree: 4)
        XCTAssertEqual(x, 160, accuracy: 1e-10)
    }

    func testXPositionWrapsAroundNorth() {
        // Heading = 5°, landmark at 355° → diff should be -10°, not 350°
        let x = CompassBarLogic.xPosition(forDegree: 355, heading: 5, centerX: 200, ptsPerDegree: 4)
        XCTAssertEqual(x, 160, accuracy: 1e-10)  // 200 + (-10 * 4) = 160
    }

    // MARK: - CompassBarView constants

    func testFovHalfAngle() {
        XCTAssertEqual(CompassBarView.fovHalfAngle, 30.0)
    }

    func testDegreesVisible() {
        XCTAssertEqual(CompassBarView.degreesVisible, 90.0)
    }
}
