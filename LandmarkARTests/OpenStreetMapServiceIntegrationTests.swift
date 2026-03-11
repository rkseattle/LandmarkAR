import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - OpenStreetMapServiceIntegrationTests
// Live network tests against the Overpass API.
// Skipped by default — set the RUN_INTEGRATION_TESTS=1 environment variable to run.

final class OpenStreetMapServiceIntegrationTests: XCTestCase {

    private var service: OpenStreetMapService!
    private var wikipediaService: WikipediaService!
    private var settings: AppSettings!

    private let seattle = CLLocation(latitude: 47.6062, longitude: -122.3321)

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        service = OpenStreetMapService()
        wikipediaService = WikipediaService()
        settings = AppSettings()
    }

    // MARK: - Basic fetch

    func testFetchReturnsLandmarksNearSeattle() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        XCTAssertFalse(landmarks.isEmpty, "Expected OSM landmarks near Seattle")
    }

    func testFetchedLandmarksHaveNonEmptyTitles() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        for landmark in landmarks {
            XCTAssertFalse(landmark.title.isEmpty, "OSM landmark title should not be empty")
        }
    }

    func testFetchedLandmarksHaveOSMIDPrefix() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        for landmark in landmarks {
            XCTAssertTrue(landmark.id.hasPrefix("osm-"),
                          "OSM landmark IDs should start with 'osm-', got: \(landmark.id)")
        }
    }

    // MARK: - Coordinates and distance

    func testFetchedLandmarksAreWithinSearchRadius() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        let radiusMeters = settings.maxDistanceKm * 1000
        for landmark in landmarks {
            XCTAssertLessThanOrEqual(landmark.distance, radiusMeters + 100,
                                     "\(landmark.title) is outside the search radius")
        }
    }

    func testFetchedLandmarksAreSortedByDistanceAscending() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        guard landmarks.count > 1 else { return }
        for i in 0..<(landmarks.count - 1) {
            XCTAssertLessThanOrEqual(landmarks[i].distance, landmarks[i + 1].distance,
                                     "OSM landmarks not sorted by distance at index \(i)")
        }
    }

    func testFetchedLandmarksHaveValidCoordinates() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        for landmark in landmarks {
            XCTAssertGreaterThan(landmark.coordinate.latitude, -90)
            XCTAssertLessThan(landmark.coordinate.latitude, 90)
            XCTAssertGreaterThan(landmark.coordinate.longitude, -180)
            XCTAssertLessThan(landmark.coordinate.longitude, 180)
        }
    }

    // MARK: - Categories

    func testFetchedLandmarksHaveValidCategories() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        let valid: Set<LandmarkCategory> = [.historical, .natural, .cultural, .other]
        for landmark in landmarks {
            XCTAssertTrue(valid.contains(landmark.category),
                          "Unexpected category for \(landmark.title)")
        }
    }

    // MARK: - Disabled source

    func testReturnsEmptyWhenOSMDisabled() async throws {
        settings.isOpenStreetMapEnabled = false
        let landmarks = try await service.fetchNearbyLandmarks(
            near: seattle, settings: settings, wikipediaService: wikipediaService
        )
        XCTAssertTrue(landmarks.isEmpty, "Should return empty when OSM is disabled")
    }
}
