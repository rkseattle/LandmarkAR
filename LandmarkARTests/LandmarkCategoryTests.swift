import XCTest
@testable import LandmarkAR

final class LandmarkCategoryTests: XCTestCase {

    // MARK: - Historical

    func testHistoricalByTitle() {
        XCTAssertEqual(LandmarkCategory.classify(title: "National Museum", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "Fort Discovery", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "War Memorial", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "Old Cemetery", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "St. Paul Cathedral", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "Ancient Ruins", summary: ""), .historical)
    }

    func testHistoricalBySummary() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Unknown Place", summary: "A historic site from the colonial era"), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "Random Title", summary: "Built as a castle in 1200"), .historical)
    }

    // MARK: - Natural

    func testNaturalByTitle() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Blue Mountain Peak", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Mirror Lake", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Redwood Forest", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Sandy Beach", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Rocky Ridge", summary: ""), .natural)
    }

    func testNaturalBySummary() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Unnamed", summary: "A beautiful waterfall in the wilderness"), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Random", summary: "National park with botanical garden"), .natural)
    }

    // MARK: - Cultural

    func testCulturalByTitle() {
        XCTAssertEqual(LandmarkCategory.classify(title: "City Hall", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Opera House", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Art Gallery", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "State University", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "City Library", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Grand Plaza", summary: ""), .cultural)
    }

    func testCulturalBySummary() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Random Place", summary: "Home to a famous theater and concert venue"), .cultural)
    }

    // MARK: - Other (fallback)

    func testOtherFallback() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Unnamed Place", summary: ""), .other)
        XCTAssertEqual(LandmarkCategory.classify(title: "Joe's Diner", summary: ""), .other)
        XCTAssertEqual(LandmarkCategory.classify(title: "12345", summary: ""), .other)
    }

    // MARK: - Priority

    func testHistoricalTakesPriorityOverNatural() {
        // "historic" matches historical, "park" matches natural — historical wins (checked first)
        XCTAssertEqual(LandmarkCategory.classify(title: "Historic Park", summary: ""), .historical)
    }

    func testNaturalTakesPriorityOverCultural() {
        // "garden" matches natural, "center" matches cultural — natural wins
        XCTAssertEqual(LandmarkCategory.classify(title: "Garden Center", summary: ""), .natural)
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveTitle() {
        XCTAssertEqual(LandmarkCategory.classify(title: "MUSEUM OF HISTORY", summary: ""), .historical)
        XCTAssertEqual(LandmarkCategory.classify(title: "NATIONAL PARK", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "ART GALLERY", summary: ""), .cultural)
    }

    func testCaseInsensitiveSummary() {
        XCTAssertEqual(LandmarkCategory.classify(title: "X", summary: "A FAMOUS MONUMENT"), .historical)
    }

    // MARK: - System image names

    func testSystemImageNames() {
        XCTAssertEqual(LandmarkCategory.historical.systemImageName, "building.columns.fill")
        XCTAssertEqual(LandmarkCategory.natural.systemImageName, "mountain.2.fill")
        XCTAssertEqual(LandmarkCategory.cultural.systemImageName, "theatermasks.fill")
        XCTAssertEqual(LandmarkCategory.other.systemImageName, "mappin.circle.fill")
    }

    // MARK: - Substring-pitfall regression

    // "bridge" contains the natural keyword "ridge" as a trailing substring.
    // The word-level classifier must not fire on "ridge" when the full word is "bridge".
    func testBridgeClassifiedAsCultural() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Golden Gate Bridge", summary: ""), .cultural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Brooklyn Bridge", summary: ""), .cultural)
    }

    func testRidgeAloneRemainsNatural() {
        XCTAssertEqual(LandmarkCategory.classify(title: "Blue Ridge", summary: ""), .natural)
        XCTAssertEqual(LandmarkCategory.classify(title: "Rocky Ridge Overlook", summary: ""), .natural)
    }

    // MARK: - Edge cases

    func testEmptyInputsClassifyAsOther() {
        XCTAssertEqual(LandmarkCategory.classify(title: "", summary: ""), .other)
    }

    func testWhitespaceOnlyInputsClassifyAsOther() {
        XCTAssertEqual(LandmarkCategory.classify(title: "   ", summary: "   "), .other)
    }

    // MARK: - Raw values

    func testRawValues() {
        XCTAssertEqual(LandmarkCategory.historical.rawValue, "historical")
        XCTAssertEqual(LandmarkCategory.natural.rawValue, "natural")
        XCTAssertEqual(LandmarkCategory.cultural.rawValue, "cultural")
        XCTAssertEqual(LandmarkCategory.other.rawValue, "other")
    }
}
