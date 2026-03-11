import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - ElevationServiceIntegrationTests
// Live network tests against the Open-Elevation API.
// Skipped by default — set the RUN_INTEGRATION_TESTS=1 environment variable to run.

final class ElevationServiceIntegrationTests: XCTestCase {

    private var service: ElevationService!

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        service = ElevationService()
    }

    // MARK: - Helpers

    private func makeLandmark(id: String, lat: Double, lon: Double) -> Landmark {
        Landmark(
            id: id,
            title: id,
            summary: "",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            wikipediaURL: nil,
            category: .other
        )
    }

    // MARK: - Basic fetch

    func testFetchElevationsReturnsResultsForKnownLandmarks() async throws {
        let landmarks = [
            makeLandmark(id: "seattle",  lat: 47.6062, lon: -122.3321),
            makeLandmark(id: "portland", lat: 45.5051, lon: -122.6750),
        ]
        let elevations = await service.fetchElevations(for: landmarks)
        XCTAssertFalse(elevations.isEmpty, "Expected elevation results")
    }

    func testSeattleElevationIsPlausible() async throws {
        // Seattle is a coastal city; elevation should be low (roughly 0–200 m).
        let landmarks = [makeLandmark(id: "seattle", lat: 47.6062, lon: -122.3321)]
        let elevations = await service.fetchElevations(for: landmarks)
        let elevation = try XCTUnwrap(elevations["seattle"])
        XCTAssertGreaterThan(elevation, -10, "Seattle elevation should be above sea level")
        XCTAssertLessThan(elevation, 500, "Seattle elevation should be below 500 m")
    }

    func testMountRainierElevationIsHigh() async throws {
        // Mount Rainier summit is ~4,392 m above sea level.
        let landmarks = [makeLandmark(id: "rainier", lat: 46.8523, lon: -121.7603)]
        let elevations = await service.fetchElevations(for: landmarks)
        let elevation = try XCTUnwrap(elevations["rainier"])
        XCTAssertGreaterThan(elevation, 3_000, "Mount Rainier elevation should be > 3000 m")
        XCTAssertLessThan(elevation, 5_000, "Mount Rainier elevation should be < 5000 m")
    }

    // MARK: - Batch fetch

    func testBatchFetchReturnsElevationForEachLandmark() async throws {
        let landmarks = [
            makeLandmark(id: "seattle",  lat: 47.6062, lon: -122.3321),
            makeLandmark(id: "rainier",  lat: 46.8523, lon: -121.7603),
            makeLandmark(id: "portland", lat: 45.5051, lon: -122.6750),
        ]
        let elevations = await service.fetchElevations(for: landmarks)
        XCTAssertEqual(elevations.count, landmarks.count,
                       "Should return an elevation entry for each landmark")
    }

    func testSkipsLandmarksWithExistingAltitude() async throws {
        var landmark = makeLandmark(id: "already-has-alt", lat: 47.6062, lon: -122.3321)
        landmark.altitude = 50.0
        let elevations = await service.fetchElevations(for: [landmark])
        // Service should skip landmarks that already have altitude — result should be empty
        XCTAssertNil(elevations["already-has-alt"],
                     "Should not re-fetch elevation for landmarks that already have altitude")
    }

    func testReturnsEmptyForEmptyInput() async throws {
        let elevations = await service.fetchElevations(for: [])
        XCTAssertTrue(elevations.isEmpty, "Should return empty dictionary for empty input")
    }
}
