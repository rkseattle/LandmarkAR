import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - WikipediaServiceIntegrationTests
// Live network tests against the Wikipedia GeoSearch and Summary APIs.
// Skipped by default — set the RUN_INTEGRATION_TESTS=1 environment variable to run.
// In Xcode: Product > Scheme > Edit Scheme > Test > Arguments > Environment Variables.

final class WikipediaServiceIntegrationTests: XCTestCase {

    private var service: WikipediaService!
    private var settings: AppSettings!

    // Seattle city centre — dense Wikipedia coverage, good for integration testing.
    private let seattle = CLLocation(latitude: 47.6062, longitude: -122.3321)

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        service = WikipediaService()
        settings = AppSettings()
    }

    // MARK: - Basic fetch

    func testFetchReturnsLandmarksNearSeattle() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        XCTAssertFalse(landmarks.isEmpty, "Expected landmarks near Seattle")
    }

    func testFetchedLandmarksHaveNonEmptyTitles() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        for landmark in landmarks {
            XCTAssertFalse(landmark.title.isEmpty, "Landmark title should not be empty")
        }
    }

    func testFetchedLandmarksHaveSummaries() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        // Most landmarks should have a non-empty summary; allow a small number of misses
        let withSummary = landmarks.filter { !$0.summary.isEmpty }
        XCTAssertGreaterThan(withSummary.count, landmarks.count / 2,
                             "More than half of landmarks should have summaries")
    }

    func testFetchedLandmarksHaveValidCategories() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        let valid: Set<LandmarkCategory> = [.historical, .natural, .cultural, .other]
        for landmark in landmarks {
            XCTAssertTrue(valid.contains(landmark.category),
                          "Unexpected category for \(landmark.title): \(landmark.category)")
        }
    }

    // MARK: - Coordinates and distance

    func testFetchedLandmarksAreWithinSearchRadius() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        let radiusMeters = min(settings.maxDistanceKm * 1000, 10_000)
        for landmark in landmarks {
            XCTAssertLessThanOrEqual(landmark.distance, radiusMeters + 100,
                                     "\(landmark.title) is outside the search radius")
        }
    }

    func testFetchedLandmarksHaveValidCoordinates() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        for landmark in landmarks {
            XCTAssertGreaterThan(landmark.coordinate.latitude, -90)
            XCTAssertLessThan(landmark.coordinate.latitude, 90)
            XCTAssertGreaterThan(landmark.coordinate.longitude, -180)
            XCTAssertLessThan(landmark.coordinate.longitude, 180)
        }
    }

    func testFetchedLandmarksHavePositiveDistance() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        for landmark in landmarks {
            XCTAssertGreaterThanOrEqual(landmark.distance, 0,
                                        "\(landmark.title) has negative distance")
        }
    }

    // MARK: - Significance scoring

    func testFetchedLandmarksHaveNonNegativeSignificanceScores() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        for landmark in landmarks {
            XCTAssertGreaterThanOrEqual(landmark.significanceScore, 0,
                                        "\(landmark.title) has negative significance score")
        }
    }

    func testFetchedLandmarksMeetMinimumPageviewThreshold() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        // Landmarks with known pageviews should all meet the minimum threshold
        let withKnownViews = landmarks.filter { $0.pageviews != nil }
        for landmark in withKnownViews {
            XCTAssertGreaterThanOrEqual(landmark.pageviews!, WikipediaService.minPageviewThreshold,
                                        "\(landmark.title) is below the significance threshold")
        }
    }

    func testLandmarksAreSortedBySignificanceDescending() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        guard landmarks.count > 1 else { return }
        for i in 0..<(landmarks.count - 1) {
            XCTAssertGreaterThanOrEqual(
                landmarks[i].significanceScore,
                landmarks[i + 1].significanceScore,
                "Landmarks not sorted by significance at index \(i)"
            )
        }
    }

    // MARK: - Wikipedia URLs

    func testFetchedLandmarksHaveWikipediaURLs() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        let withURL = landmarks.filter { $0.wikipediaURL != nil }
        XCTAssertFalse(withURL.isEmpty, "At least some landmarks should have Wikipedia URLs")
    }

    func testWikipediaURLsUseHTTPS() async throws {
        let landmarks = try await service.fetchNearbyLandmarks(near: seattle, settings: settings)
        for landmark in landmarks.compactMap({ $0.wikipediaURL }) {
            XCTAssertEqual(landmark.scheme, "https", "Wikipedia URL should use HTTPS: \(landmark)")
        }
    }

    // MARK: - Language support

    func testFetchInJapaneseNearTokyo() async throws {
        let tokyo = CLLocation(latitude: 35.6762, longitude: 139.6503)
        settings.appLanguage = .japanese
        let landmarks = try await service.fetchNearbyLandmarks(near: tokyo, settings: settings)
        XCTAssertFalse(landmarks.isEmpty, "Expected landmarks near Tokyo in Japanese")
    }
}
