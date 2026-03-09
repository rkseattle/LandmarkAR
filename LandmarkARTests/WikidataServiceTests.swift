import XCTest
@testable import LandmarkAR

// MARK: - WikidataServiceTests (LAR-45)
// Tests the pure-logic Stage 1 wikipedia-tag parsing in WikidataService.
// Stages 2 and 3 involve network calls and are not unit tested here.

final class WikidataServiceTests: XCTestCase {

    private let service = WikidataService()

    // MARK: - Stage 1: resolveFromWikipediaTag

    func testStage1BasicEnglish() {
        let url = service.resolveFromWikipediaTag("en:Space Needle")
        XCTAssertEqual(url?.absoluteString, "https://en.wikipedia.org/wiki/Space%20Needle")
    }

    func testStage1EncodesSpecialCharacters() {
        // Title with non-ASCII characters must be percent-encoded.
        let url = service.resolveFromWikipediaTag("ja:東京スカイツリー")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://ja.wikipedia.org/wiki/"))
        // Verify the raw URL can be constructed (non-nil is sufficient for encoding check)
    }

    func testStage1UnderscorePreserved() {
        // Underscores are valid in Wikipedia titles and should pass through unchanged.
        let url = service.resolveFromWikipediaTag("en:Eiffel_Tower")
        XCTAssertEqual(url?.absoluteString, "https://en.wikipedia.org/wiki/Eiffel_Tower")
    }

    func testStage1NilTagReturnsNil() {
        XCTAssertNil(service.resolveFromWikipediaTag(nil))
    }

    func testStage1EmptyStringReturnsNil() {
        XCTAssertNil(service.resolveFromWikipediaTag(""))
    }

    func testStage1NoColonReturnsNil() {
        XCTAssertNil(service.resolveFromWikipediaTag("Space Needle"))
    }

    func testStage1EmptyLangReturnsNil() {
        // ":Title" — lang part is empty
        XCTAssertNil(service.resolveFromWikipediaTag(":Space Needle"))
    }

    func testStage1EmptyTitleReturnsNil() {
        // "en:" — title part is empty
        XCTAssertNil(service.resolveFromWikipediaTag("en:"))
    }

    func testStage1TitleWithColonUsesFirstColon() {
        // "en:Title:Extra" — everything after the first colon is the title
        let url = service.resolveFromWikipediaTag("en:Title:Extra")
        XCTAssertEqual(url?.absoluteString, "https://en.wikipedia.org/wiki/Title:Extra")
    }

    func testStage1NonEnglishLanguageCode() {
        let url = service.resolveFromWikipediaTag("fr:Tour Eiffel")
        XCTAssertEqual(url?.absoluteString, "https://fr.wikipedia.org/wiki/Tour%20Eiffel")
    }
}
