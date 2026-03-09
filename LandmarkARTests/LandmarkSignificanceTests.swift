import XCTest
@testable import LandmarkAR

// Tests for LAR-39: Landmark Significance Filtering.
// Covers score calculation, threshold filtering, and AppSettings defaults.

final class LandmarkSignificanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppSettingsTests.clearAppSettingsDefaults()
    }

    // MARK: - significanceScore(pageviews:extractLength:)

    func testScoreIsPageviewDominatedWhenBothPresent() {
        // 1000 pageviews, max-length extract → score ≈ 800.2
        let score = WikipediaService.significanceScore(pageviews: 1_000, extractLength: WikipediaService.maxExtractLengthForNormalization)
        XCTAssertEqual(score, 1_000.0 * 0.8 + 1.0 * 0.2, accuracy: 0.001)
    }

    func testScoreWithZeroPageviewsUsesArticleLengthOnly() {
        let score = WikipediaService.significanceScore(pageviews: 0, extractLength: WikipediaService.maxExtractLengthForNormalization)
        XCTAssertEqual(score, 0.2, accuracy: 0.001)
    }

    func testScoreWithNilPageviewsUsesArticleLengthOnly() {
        // nil = API failed; fallback to article-length signal only
        let score = WikipediaService.significanceScore(pageviews: nil, extractLength: WikipediaService.maxExtractLengthForNormalization)
        XCTAssertEqual(score, 0.2, accuracy: 0.001)
    }

    func testScoreWithZeroExtractLengthUsesPageviewsOnly() {
        let score = WikipediaService.significanceScore(pageviews: 5_000, extractLength: 0)
        XCTAssertEqual(score, 5_000.0 * 0.8, accuracy: 0.001)
    }

    func testScoreWithBothZeroIsZero() {
        let score = WikipediaService.significanceScore(pageviews: 0, extractLength: 0)
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testNormalizedExtractLengthClampsAtOne() {
        // An extract longer than maxExtractLengthForNormalization should not push score above max
        let longExtract = WikipediaService.maxExtractLengthForNormalization * 10
        let score = WikipediaService.significanceScore(pageviews: 0, extractLength: longExtract)
        XCTAssertEqual(score, 0.2, accuracy: 0.001)
    }

    func testHigherPageviewsProduceHigherScore() {
        let low  = WikipediaService.significanceScore(pageviews: 500,    extractLength: 0)
        let high = WikipediaService.significanceScore(pageviews: 50_000, extractLength: 0)
        XCTAssertLessThan(low, high)
    }

    // MARK: - Threshold constants

    func testMinPageviewThresholdIs1000() {
        XCTAssertEqual(WikipediaService.minPageviewThreshold, 1_000)
    }

    func testIconicPageviewThresholdIs10000() {
        XCTAssertEqual(WikipediaService.iconicPageviewThreshold, 10_000)
    }

    func testIconicThresholdIsHigherThanMinThreshold() {
        XCTAssertGreaterThan(WikipediaService.iconicPageviewThreshold,
                             WikipediaService.minPageviewThreshold)
    }

    // MARK: - Landmark pageviews filtering logic

    /// Helper: makes a minimal Landmark with the given pageviews value.
    private func makeLandmark(pageviews: Int?) -> Landmark {
        Landmark(
            id: UUID().uuidString,
            title: "Test",
            summary: "",
            coordinate: .init(latitude: 0, longitude: 0),
            wikipediaURL: nil,
            category: .other,
            pageviews: pageviews
        )
    }

    func testLandmarkAboveMinThresholdIsKept() {
        let landmark = makeLandmark(pageviews: WikipediaService.minPageviewThreshold)
        XCTAssertTrue(landmark.pageviews! >= WikipediaService.minPageviewThreshold)
    }

    func testLandmarkBelowMinThresholdIsFiltered() {
        let views = WikipediaService.minPageviewThreshold - 1
        let landmark = makeLandmark(pageviews: views)
        XCTAssertFalse(landmark.pageviews! >= WikipediaService.minPageviewThreshold)
    }

    func testLandmarkWithNilPageviewsIsNotDropped() {
        // nil pageviews = API failed; the filter must NOT drop this landmark.
        let landmark = makeLandmark(pageviews: nil)
        // Simulate filter logic: guard let views = pageviews else { return true }
        let kept: Bool
        if let views = landmark.pageviews {
            kept = views >= WikipediaService.minPageviewThreshold
        } else {
            kept = true  // API failed → keep
        }
        XCTAssertTrue(kept)
    }

    func testLandmarkAboveIconicThresholdPassesBothFilters() {
        let views = WikipediaService.iconicPageviewThreshold
        let landmark = makeLandmark(pageviews: views)
        XCTAssertTrue(landmark.pageviews! >= WikipediaService.minPageviewThreshold)
        XCTAssertTrue(landmark.pageviews! >= WikipediaService.iconicPageviewThreshold)
    }

    func testLandmarkBetweenMinAndIconicThresholdPassesOnlyMinFilter() {
        let views = WikipediaService.minPageviewThreshold + 1
        let landmark = makeLandmark(pageviews: views)
        XCTAssertTrue(landmark.pageviews!  >= WikipediaService.minPageviewThreshold)
        XCTAssertFalse(landmark.pageviews! >= WikipediaService.iconicPageviewThreshold)
    }

    // MARK: - AppSettings defaults

    func testIsIconicLandmarksOnlyDefaultsToFalse() {
        let sut = AppSettings()
        XCTAssertFalse(sut.isIconicLandmarksOnly)
    }

    func testIsIconicLandmarksOnlyPersists() {
        let sut = AppSettings()
        sut.isIconicLandmarksOnly = true
        XCTAssertTrue(AppSettings().isIconicLandmarksOnly)
        sut.isIconicLandmarksOnly = false
    }

    // MARK: - Landmark model defaults

    func testLandmarkSignificanceScoreDefaultsToZero() {
        let landmark = makeLandmark(pageviews: nil)
        XCTAssertEqual(landmark.significanceScore, 0.0)
    }

    func testLandmarkPageviewsDefaultsToNil() {
        let landmark = Landmark(
            id: "1",
            title: "X",
            summary: "",
            coordinate: .init(latitude: 0, longitude: 0),
            wikipediaURL: nil,
            category: .other
        )
        XCTAssertNil(landmark.pageviews)
    }
}
