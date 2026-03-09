import XCTest
@testable import LandmarkAR

// Tests for LAR-46: Visible label cap and geo-search pool size.
// Verifies that the two tuning constants are set correctly relative to each other
// and that the significance-sort ordering used for capping is stable.

final class VisibleLabelCapTests: XCTestCase {

    // MARK: - Constant values

    func testGeoSearchLimitIs50() {
        XCTAssertEqual(WikipediaService.geoSearchLimit, 50)
    }

    func testMaxVisibleLabelsIs10() {
        XCTAssertEqual(ARLandmarkViewController.maxVisibleLabels, 10)
    }

    /// The candidate pool must be larger than the on-screen cap so that landmarks
    /// behind the user don't starve the visible arc of labels.
    func testGeoSearchLimitIsGreaterThanMaxVisibleLabels() {
        XCTAssertGreaterThan(WikipediaService.geoSearchLimit,
                             ARLandmarkViewController.maxVisibleLabels)
    }

    // MARK: - Significance-sort ordering (mirrors WikipediaService sort used before capping)

    private func makeLandmark(id: String, significanceScore: Double, distance: Double) -> Landmark {
        Landmark(
            id: id,
            title: id,
            summary: "",
            coordinate: .init(latitude: 0, longitude: 0),
            wikipediaURL: nil,
            category: .other,
            distance: distance,
            significanceScore: significanceScore
        )
    }

    func testHigherSignificanceLandmarkRanksFirst() {
        let low  = makeLandmark(id: "low",  significanceScore: 100,  distance: 50)
        let high = makeLandmark(id: "high", significanceScore: 5000, distance: 200)
        let sorted = [low, high].sorted {
            if $0.significanceScore != $1.significanceScore { return $0.significanceScore > $1.significanceScore }
            return $0.distance < $1.distance
        }
        XCTAssertEqual(sorted.first?.id, "high")
    }

    func testDistanceBreaksTieWhenSignificanceIsEqual() {
        let far   = makeLandmark(id: "far",   significanceScore: 500, distance: 800)
        let close = makeLandmark(id: "close", significanceScore: 500, distance: 100)
        let sorted = [far, close].sorted {
            if $0.significanceScore != $1.significanceScore { return $0.significanceScore > $1.significanceScore }
            return $0.distance < $1.distance
        }
        XCTAssertEqual(sorted.first?.id, "close")
    }

    func testPrefixLimitRetainsHighestRankedEntries() {
        // Simulate what refreshLabels() does: take .prefix(maxVisibleLabels) from on-screen list.
        let landmarks = (1...15).map { i in
            makeLandmark(id: "L\(i)", significanceScore: Double(i) * 100, distance: Double(i) * 10)
        }.sorted {
            $0.significanceScore > $1.significanceScore // highest first
        }
        let capped = Array(landmarks.prefix(ARLandmarkViewController.maxVisibleLabels))
        XCTAssertEqual(capped.count, ARLandmarkViewController.maxVisibleLabels)
        // All capped entries should have higher significance than any excluded entry.
        let cappedMin = capped.map(\.significanceScore).min()!
        let excluded  = landmarks.dropFirst(ARLandmarkViewController.maxVisibleLabels)
        if let excludedMax = excluded.map(\.significanceScore).max() {
            XCTAssertGreaterThanOrEqual(cappedMin, excludedMax)
        }
    }
}
