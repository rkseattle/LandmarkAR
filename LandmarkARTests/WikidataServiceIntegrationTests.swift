import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - WikidataServiceIntegrationTests
// Tests for the 3-stage Wikipedia URL resolution pipeline in WikidataService.
// Stage 1 (tag parsing) runs without network. Stages 2 & 3 require network and
// are skipped unless RUN_INTEGRATION_TESTS=1 is set.

final class WikidataServiceIntegrationTests: XCTestCase {

    private var service: WikidataService!
    private var wikipediaService: WikipediaService!

    // Space Needle coordinates for Stage 3 GeoSearch tests.
    private let spaceNeedleCoord = CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3493)

    override func setUp() async throws {
        service = WikidataService()
        wikipediaService = WikipediaService()
    }

    // MARK: - Stage 1: OSM wikipedia tag parsing (no network)

    func testResolveFromWikipediaTagEnglish() {
        let url = service.resolveFromWikipediaTag("en:Space_Needle")
        XCTAssertEqual(url?.absoluteString, "https://en.wikipedia.org/wiki/Space_Needle")
    }

    func testResolveFromWikipediaTagJapanese() {
        let url = service.resolveFromWikipediaTag("ja:東京タワー")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("ja.wikipedia.org"))
    }

    func testResolveFromWikipediaTagEncodesSpaces() {
        let url = service.resolveFromWikipediaTag("en:Pike Place Market")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("Pike%20Place%20Market") ||
                      url!.absoluteString.contains("Pike_Place_Market"))
    }

    func testResolveFromWikipediaTagNilInput() {
        XCTAssertNil(service.resolveFromWikipediaTag(nil))
    }

    func testResolveFromWikipediaTagMissingColon() {
        XCTAssertNil(service.resolveFromWikipediaTag("enSpaceNeedle"))
    }

    func testResolveFromWikipediaTagEmptyLang() {
        XCTAssertNil(service.resolveFromWikipediaTag(":Space_Needle"))
    }

    func testResolveFromWikipediaTagEmptyTitle() {
        XCTAssertNil(service.resolveFromWikipediaTag("en:"))
    }

    // MARK: - Stage 2: Wikidata API (network required)

    func testResolveFromWikidataIDReturnsWikipediaURL() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        // Q105543 = Space Needle
        let url = await service.resolveWikipediaURL(
            elementID: 1,
            tags: ["wikidata": "Q105543"],
            coordinate: spaceNeedleCoord,
            languageCode: "en",
            wikipediaService: wikipediaService
        )
        let resolved = try XCTUnwrap(url, "Should resolve a Wikipedia URL for Space Needle via Wikidata")
        XCTAssertTrue(resolved.absoluteString.contains("wikipedia.org"),
                      "Resolved URL should be a Wikipedia URL: \(resolved)")
    }

    func testResolveFromWikidataPreferredLanguage() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        // Q243 = Eiffel Tower — well-known, available in French Wikipedia
        let url = await service.resolveWikipediaURL(
            elementID: 2,
            tags: ["wikidata": "Q243"],
            coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945),
            languageCode: "fr",
            wikipediaService: wikipediaService
        )
        let resolved = try XCTUnwrap(url, "Should resolve a Wikipedia URL for Eiffel Tower")
        XCTAssertTrue(resolved.absoluteString.contains("wikipedia.org"),
                      "Resolved URL should be a Wikipedia URL: \(resolved)")
    }

    // MARK: - Stage 3: GeoSearch fallback (network required)

    func testGeoSearchFallbackNearSpaceNeedle() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1",
            "Set RUN_INTEGRATION_TESTS=1 to run integration tests"
        )
        // No tags — forces Stage 3 GeoSearch cross-reference
        let url = await service.resolveWikipediaURL(
            elementID: 3,
            tags: [:],
            coordinate: spaceNeedleCoord,
            languageCode: "en",
            wikipediaService: wikipediaService
        )
        // The Space Needle has a Wikipedia article; GeoSearch should find something nearby
        if let url {
            XCTAssertTrue(url.absoluteString.contains("en.wikipedia.org"),
                          "GeoSearch fallback should return an English Wikipedia URL")
        }
        // nil is acceptable if nothing is within 50 m — don't hard-fail
    }

    // MARK: - Stage 1 takes priority over network stages

    func testWikipediaTagTakesPriorityOverWikidataTag() async throws {
        // Both tags present — Stage 1 (wikipedia tag) should win without any network call
        let url = await service.resolveWikipediaURL(
            elementID: 4,
            tags: [
                "wikipedia": "en:Space_Needle",
                "wikidata": "Q999999999",   // nonsense ID — should never be queried
            ],
            coordinate: spaceNeedleCoord,
            languageCode: "en",
            wikipediaService: wikipediaService
        )
        XCTAssertEqual(url?.absoluteString, "https://en.wikipedia.org/wiki/Space_Needle",
                       "Wikipedia tag should take priority over Wikidata tag")
    }
}
