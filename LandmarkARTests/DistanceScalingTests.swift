import XCTest
@testable import LandmarkAR

// MARK: - DistanceScalingTests (LAR-43)
// Tests the logarithmic scale factor used to size AR labels by distance.

final class DistanceScalingTests: XCTestCase {

    // MARK: - scaleFactor boundary values

    func test_scaleFactor_atMinDistance_returnsOne() {
        let factor = LabelDisplaySize.scaleFactor(for: LabelDisplaySize.minScaleDistanceMeters)
        XCTAssertEqual(factor, 1.0, accuracy: 0.001)
    }

    func test_scaleFactor_atMaxDistance_returnsZero() {
        let factor = LabelDisplaySize.scaleFactor(for: LabelDisplaySize.maxScaleDistanceMeters)
        XCTAssertEqual(factor, 0.0, accuracy: 0.001)
    }

    func test_scaleFactor_belowMinDistance_clampedToOne() {
        XCTAssertEqual(LabelDisplaySize.scaleFactor(for: 0),   1.0, accuracy: 0.001)
        XCTAssertEqual(LabelDisplaySize.scaleFactor(for: 50),  1.0, accuracy: 0.001)
        XCTAssertEqual(LabelDisplaySize.scaleFactor(for: 199), 1.0, accuracy: 0.001)
    }

    func test_scaleFactor_aboveMaxDistance_clampedToZero() {
        XCTAssertEqual(LabelDisplaySize.scaleFactor(for: 5001),  0.0, accuracy: 0.001)
        XCTAssertEqual(LabelDisplaySize.scaleFactor(for: 10000), 0.0, accuracy: 0.001)
    }

    func test_scaleFactor_midpoint_isBetweenZeroAndOne() {
        let factor = LabelDisplaySize.scaleFactor(for: 1000)
        XCTAssertGreaterThan(factor, 0.0)
        XCTAssertLessThan(factor, 1.0)
    }

    // MARK: - Monotonically decreasing

    func test_scaleFactor_decreasesWithDistance() {
        let distances: [Double] = [200, 500, 1000, 2000, 3500, 5000]
        var previous = LabelDisplaySize.scaleFactor(for: distances[0])
        for distance in distances.dropFirst() {
            let current = LabelDisplaySize.scaleFactor(for: distance)
            XCTAssertLessThanOrEqual(current, previous,
                "scaleFactor should decrease as distance increases (failed at \(distance)m)")
            previous = current
        }
    }

    // MARK: - LabelDisplaySize max sizes

    func test_maxDistanceFontSize_is65PercentOfTitleFont() {
        for size in LabelDisplaySize.allCases {
            let expected = (size.maxTitleFontSize * 0.65).rounded()
            XCTAssertEqual(size.maxDistanceFontSize, expected,
                           "maxDistanceFontSize for \(size) should be 65% of maxTitleFontSize")
        }
    }

    func test_minTitleFontSize_doesNotExceedMaxForAnySize() {
        for size in LabelDisplaySize.allCases {
            XCTAssertLessThanOrEqual(LabelDisplaySize.minTitleFontSize, size.maxTitleFontSize,
                "minTitleFontSize must not exceed maxTitleFontSize for \(size)")
        }
    }

    // MARK: - Computed scale stays above minimum floor

    func test_computedScale_atMaxDistance_meetsMinFontFloor() {
        for size in LabelDisplaySize.allCases {
            let factor = LabelDisplaySize.scaleFactor(for: LabelDisplaySize.maxScaleDistanceMeters)
            let minScale = LabelDisplaySize.minTitleFontSize / size.maxTitleFontSize
            let scale = minScale + (1.0 - minScale) * factor
            let resultingFontSize = size.maxTitleFontSize * scale
            XCTAssertGreaterThanOrEqual(resultingFontSize, LabelDisplaySize.minTitleFontSize - 0.001,
                "Title font at max distance must be ≥ minTitleFontSize for display size \(size)")
        }
    }
}
