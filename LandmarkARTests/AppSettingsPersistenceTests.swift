import XCTest
@testable import LandmarkAR

// Tests that AppSettings correctly round-trips each property through UserDefaults.
// Immediate-write properties (toggles, pickers) are verified via a second AppSettings()
// instance; deferred-write properties (distance sliders) are verified in-memory only
// since the 0.3 s debounce makes synchronous UserDefaults reads unreliable in tests.

final class AppSettingsPersistenceTests: XCTestCase {

    // MARK: - Immediate-write properties

    func testIsWikipediaEnabledPersists() {
        let sut = AppSettings()
        let original = sut.isWikipediaEnabled
        sut.isWikipediaEnabled = false
        XCTAssertEqual(AppSettings().isWikipediaEnabled, false)
        sut.isWikipediaEnabled = original
    }

    func testIsOpenStreetMapEnabledPersists() {
        let sut = AppSettings()
        let original = sut.isOpenStreetMapEnabled
        sut.isOpenStreetMapEnabled = false
        XCTAssertEqual(AppSettings().isOpenStreetMapEnabled, false)
        sut.isOpenStreetMapEnabled = original
    }

    func testMaxLandmarkCountPersists() {
        let sut = AppSettings()
        let original = sut.maxLandmarkCount
        sut.maxLandmarkCount = 5
        XCTAssertEqual(AppSettings().maxLandmarkCount, 5)
        sut.maxLandmarkCount = original
    }

    func testLabelDisplaySizePersists() {
        let sut = AppSettings()
        let original = sut.labelDisplaySize
        sut.labelDisplaySize = .large
        XCTAssertEqual(AppSettings().labelDisplaySize, .large)
        sut.labelDisplaySize = original
    }

    func testRealtimeUpdateModePersists() {
        let sut = AppSettings()
        let original = sut.realtimeUpdateMode
        sut.realtimeUpdateMode = .always
        XCTAssertEqual(AppSettings().realtimeUpdateMode, .always)
        sut.realtimeUpdateMode = original
    }

    func testShowHistoricalPersists() {
        let sut = AppSettings()
        let original = sut.showHistorical
        sut.showHistorical = false
        XCTAssertEqual(AppSettings().showHistorical, false)
        sut.showHistorical = original
    }

    func testShowNaturalPersists() {
        let sut = AppSettings()
        let original = sut.showNatural
        sut.showNatural = false
        XCTAssertEqual(AppSettings().showNatural, false)
        sut.showNatural = original
    }

    func testShowCulturalPersists() {
        let sut = AppSettings()
        let original = sut.showCultural
        sut.showCultural = false
        XCTAssertEqual(AppSettings().showCultural, false)
        sut.showCultural = original
    }

    func testShowOtherPersists() {
        let sut = AppSettings()
        let original = sut.showOther
        sut.showOther = false
        XCTAssertEqual(AppSettings().showOther, false)
        sut.showOther = original
    }

    // MARK: - Immediate-write verification (UserDefaults check)

    // Toggles must write synchronously — a new AppSettings() read must see the new value.
    func testToggleWritesAreVisibleToNewInstance() {
        let sut = AppSettings()
        let original = sut.showNatural
        sut.showNatural = !original
        // No delay — value must already be in UserDefaults
        let sut2 = AppSettings()
        XCTAssertEqual(sut2.showNatural, !original)
        sut.showNatural = original
    }

    // MARK: - Deferred-write properties (in-memory only)

    // Distance slider indices are debounced — we verify the in-memory @Published value
    // updates immediately even though the UserDefaults write is deferred.
    func testDistanceSliderIndexUpdatesInMemoryImmediately() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 0
        XCTAssertEqual(sut.maxDistanceIndexHistorical, 0)
        XCTAssertEqual(sut.maxDistanceKmHistorical, 0.1)
    }

    func testAllFourDistanceSliderIndicesUpdateInMemory() {
        let sut = AppSettings()
        sut.maxDistanceIndexHistorical = 1
        sut.maxDistanceIndexNatural    = 2
        sut.maxDistanceIndexCultural   = 3
        sut.maxDistanceIndexOther      = 5

        XCTAssertEqual(sut.maxDistanceKmHistorical, 0.5)
        XCTAssertEqual(sut.maxDistanceKmNatural,    1.0)
        XCTAssertEqual(sut.maxDistanceKmCultural,   5.0)
        XCTAssertEqual(sut.maxDistanceKmOther,      25.0)
    }
}
