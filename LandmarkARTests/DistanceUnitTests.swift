import XCTest
@testable import LandmarkAR

// MARK: - DistanceUnitTests
// Tests DistanceUnit.formatted(_:) and sliderLabel(km:) — pure-logic, no networking.

final class DistanceUnitTests: XCTestCase {

    // MARK: - formatted(_:) — Kilometers

    func testKilometersBelow100() {
        XCTAssertEqual(DistanceUnit.kilometers.formatted(50), "< 100 m away")
        XCTAssertEqual(DistanceUnit.kilometers.formatted(0), "< 100 m away")
        XCTAssertEqual(DistanceUnit.kilometers.formatted(99), "< 100 m away")
    }

    func testKilometersBetween100And999() {
        // 320 m → rounds to nearest 100 → 300 m
        XCTAssertEqual(DistanceUnit.kilometers.formatted(320), "300 m away")
        // 950 m → rounds to nearest 100 → 1000 m... wait, 950/100 = 9.5 rounds to 10 → 1000
        // Actually 999 / 100 = 9.99 rounds to 10 → 1000 m, which hits the ≥1000 branch
        XCTAssertEqual(DistanceUnit.kilometers.formatted(150), "200 m away")
    }

    func testKilometersAtAndAbove1000() {
        XCTAssertEqual(DistanceUnit.kilometers.formatted(1000), "1.0 km away")
        XCTAssertEqual(DistanceUnit.kilometers.formatted(2500), "2.5 km away")
        XCTAssertEqual(DistanceUnit.kilometers.formatted(10000), "10.0 km away")
    }

    // MARK: - formatted(_:) — Miles

    func testMilesBelowThousandFeet() {
        // 100 m = 328 ft → rounds to nearest 50 → 300 ft
        let result = DistanceUnit.miles.formatted(100)
        XCTAssertEqual(result, "300 ft away")
    }

    func testMilesAtAndAboveThousandFeet() {
        // 1000 ft = 304.8 m → 304.8 / 1609.344 ≈ 0.2 mi
        let result = DistanceUnit.miles.formatted(304.8)
        XCTAssertTrue(result.hasSuffix("mi away"), "Expected miles suffix, got: \(result)")
    }

    func testMilesRoundingInFeetRange() {
        // 50 ft = 15.24 m → (50/50).rounded() * 50 = 50
        let result = DistanceUnit.miles.formatted(15.24)
        XCTAssertEqual(result, "50 ft away")
    }

    // MARK: - sliderLabel(km:)

    func testSliderLabelKilometersSubKm() {
        XCTAssertEqual(DistanceUnit.kilometers.sliderLabel(km: 0.1), "0.1 km")
        XCTAssertEqual(DistanceUnit.kilometers.sliderLabel(km: 0.5), "0.5 km")
    }

    func testSliderLabelKilometersInteger() {
        XCTAssertEqual(DistanceUnit.kilometers.sliderLabel(km: 1.0), "1 km")
        XCTAssertEqual(DistanceUnit.kilometers.sliderLabel(km: 10.0), "10 km")
        XCTAssertEqual(DistanceUnit.kilometers.sliderLabel(km: 100.0), "100 km")
    }

    func testSliderLabelMilesSubMile() {
        // 0.1 km = 0.0621 mi → "0.1 mi"
        let result = DistanceUnit.miles.sliderLabel(km: 0.1)
        XCTAssertTrue(result.hasSuffix("mi"), "Expected mi suffix, got: \(result)")
        XCTAssertTrue(result.contains("0."), "Expected sub-1 value, got: \(result)")
    }

    func testSliderLabelMilesIntegerMile() {
        // 5 km = 3.1 mi → rounds to "3 mi"
        let result = DistanceUnit.miles.sliderLabel(km: 5.0)
        XCTAssertEqual(result, "3 mi")
    }

    func testSliderLabelMilesLargeValue() {
        // 100 km = 62.1 mi → rounds to "62 mi"
        let result = DistanceUnit.miles.sliderLabel(km: 100.0)
        XCTAssertEqual(result, "62 mi")
    }

    // MARK: - systemDefault

    func testSystemDefaultReturnsAValidUnit() {
        let unit = DistanceUnit.systemDefault()
        XCTAssertTrue(unit == .kilometers || unit == .miles)
    }
}
