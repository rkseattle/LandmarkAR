import XCTest
@testable import LandmarkAR

final class AppSettingsTests: XCTestCase {

    // MARK: - km(forIndex:)

    func testKmForIndexAllSteps() {
        XCTAssertEqual(AppSettings.km(forIndex: 0), 0.1)
        XCTAssertEqual(AppSettings.km(forIndex: 1), 0.5)
        XCTAssertEqual(AppSettings.km(forIndex: 2), 1.0)
        XCTAssertEqual(AppSettings.km(forIndex: 3), 5.0)
        XCTAssertEqual(AppSettings.km(forIndex: 4), 10.0)
        XCTAssertEqual(AppSettings.km(forIndex: 5), 25.0)
        XCTAssertEqual(AppSettings.km(forIndex: 6), 100.0)
    }

    func testKmForIndexClampsLow() {
        XCTAssertEqual(AppSettings.km(forIndex: -1), 0.1)
        XCTAssertEqual(AppSettings.km(forIndex: -100), 0.1)
    }

    func testKmForIndexClampsHigh() {
        XCTAssertEqual(AppSettings.km(forIndex: 7), 100.0)
        XCTAssertEqual(AppSettings.km(forIndex: 99), 100.0)
    }

    func testKmForIndexRounds() {
        // 2.4 rounds to 2 → 1.0 km; 2.5 rounds to 3 → 5.0 km
        XCTAssertEqual(AppSettings.km(forIndex: 2.4), 1.0)
        XCTAssertEqual(AppSettings.km(forIndex: 2.5), 5.0)
    }

    // MARK: - distanceLabel(forIndex:)

    func testDistanceLabelSubKilometer() {
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 0), "0.1 km")
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 1), "0.5 km")
    }

    func testDistanceLabelOneKmAndAbove() {
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 2), "1 km")
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 3), "5 km")
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 4), "10 km")
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 5), "25 km")
        XCTAssertEqual(AppSettings.distanceLabel(forIndex: 6), "100 km")
    }

    // MARK: - maxDistanceKm

    func testMaxDistanceKmAllEnabled() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 2   // 1 km
        sut.maxDistanceIndexNatural    = 4   // 10 km
        sut.maxDistanceIndexCultural   = 3   // 5 km
        sut.maxDistanceIndexOther      = 1   // 0.5 km
        sut.showHistorical = true
        sut.showNatural    = true
        sut.showCultural   = true
        sut.showOther      = true

        XCTAssertEqual(sut.maxDistanceKm, 10.0)
    }

    func testMaxDistanceKmRespectsEnabledCategories() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 6   // 100 km — disabled
        sut.maxDistanceIndexNatural    = 3   // 5 km  — enabled
        sut.showHistorical = false
        sut.showNatural    = true
        sut.showCultural   = false
        sut.showOther      = false

        XCTAssertEqual(sut.maxDistanceKm, 5.0)
    }

    func testMaxDistanceKmAllDisabledReturnsZero() {
        let sut = AppSettings()
        sut.showHistorical = false
        sut.showNatural    = false
        sut.showCultural   = false
        sut.showOther      = false

        XCTAssertEqual(sut.maxDistanceKm, 0.0)
    }

    func testMaxDistanceKmSingleCategory() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 5   // 25 km
        sut.showHistorical = true
        sut.showNatural    = false
        sut.showCultural   = false
        sut.showOther      = false

        XCTAssertEqual(sut.maxDistanceKm, 25.0)
    }

    // MARK: - Per-category distance helpers

    func testMaxDistanceKmProperties() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 0
        sut.maxDistanceIndexNatural    = 2
        sut.maxDistanceIndexCultural   = 4
        sut.maxDistanceIndexOther      = 6

        XCTAssertEqual(sut.maxDistanceKmHistorical, 0.1)
        XCTAssertEqual(sut.maxDistanceKmNatural,    1.0)
        XCTAssertEqual(sut.maxDistanceKmCultural,   10.0)
        XCTAssertEqual(sut.maxDistanceKmOther,      100.0)
    }

    // MARK: - LabelDisplaySize enum

    func testLabelDisplaySizeRawValues() {
        XCTAssertEqual(LabelDisplaySize.small.rawValue,  "small")
        XCTAssertEqual(LabelDisplaySize.medium.rawValue, "medium")
        XCTAssertEqual(LabelDisplaySize.large.rawValue,  "large")
    }

    func testLabelDisplaySizeRoundtrip() {
        for size in LabelDisplaySize.allCases {
            XCTAssertEqual(LabelDisplaySize(rawValue: size.rawValue), size)
        }
    }

    // MARK: - RealtimeUpdateMode enum

    func testRealtimeUpdateModeRawValues() {
        XCTAssertEqual(RealtimeUpdateMode.off.rawValue,      "off")
        XCTAssertEqual(RealtimeUpdateMode.wifiOnly.rawValue, "wifiOnly")
        XCTAssertEqual(RealtimeUpdateMode.always.rawValue,   "always")
    }

    func testRealtimeUpdateModeRoundtrip() {
        for mode in RealtimeUpdateMode.allCases {
            XCTAssertEqual(RealtimeUpdateMode(rawValue: mode.rawValue), mode)
        }
    }

    // MARK: - distanceSteps count

    func testDistanceStepsCount() {
        XCTAssertEqual(AppSettings.distanceSteps.count, 7)
    }

    // MARK: - Default values

    func testMaxLandmarkCountDefaultsTo10() {
        let sut = AppSettings()
        XCTAssertEqual(sut.maxLandmarkCount, 10)
    }

    func testLabelDisplaySizeDefaultsToMedium() {
        let sut = AppSettings()
        XCTAssertEqual(sut.labelDisplaySize, .medium)
    }

    func testRealtimeUpdateModeDefaultsToOff() {
        let sut = AppSettings()
        XCTAssertEqual(sut.realtimeUpdateMode, .off)
    }

    func testCategoryTogglesDefaultToTrue() {
        let sut = AppSettings()
        XCTAssertTrue(sut.showHistorical)
        XCTAssertTrue(sut.showNatural)
        XCTAssertTrue(sut.showCultural)
        XCTAssertTrue(sut.showOther)
    }

    // MARK: - Category toggle influence on maxDistanceKm

    func testDisablingOneToggleExcludesItFromMaxDistance() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 6  // 100 km
        sut.maxDistanceIndexNatural    = 3  // 5 km
        sut.maxDistanceIndexCultural   = 2  // 1 km
        sut.maxDistanceIndexOther      = 1  // 0.5 km
        sut.showHistorical = false
        sut.showNatural    = true
        sut.showCultural   = true
        sut.showOther      = true

        // Historical (100 km) is disabled; max of remaining is Natural (5 km)
        XCTAssertEqual(sut.maxDistanceKm, 5.0)
    }

    func testDisablingOneToggleDoesNotAffectOtherToggles() {
        let sut = AppSettings()
        sut.showHistorical = false

        XCTAssertFalse(sut.showHistorical)
        XCTAssertTrue(sut.showNatural)
        XCTAssertTrue(sut.showCultural)
        XCTAssertTrue(sut.showOther)
    }
}
