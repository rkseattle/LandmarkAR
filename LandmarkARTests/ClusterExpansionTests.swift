import XCTest
@testable import LandmarkAR

// MARK: - ClusterExpansionTests
// LAR-51: Unit tests for cluster detection.
// Cluster detection uses rect-intersection: two labels cluster when their bounding
// rects overlap. The default labelSize of 20 × 20 in detectClusters(from:labelSize:)
// preserves the original threshold-distance semantics for these tests.

final class ClusterExpansionTests: XCTestCase {

    // MARK: - Cluster Detection

    func testNoCluster_whenEntriesBeyondThreshold() {
        // Two labels 30 pt apart (centres). With 20 × 20 rects the rects don't touch.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 130, y: 200)),  // gap of 10 pt between rects
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertTrue(clusters.isEmpty)
    }

    func testCluster_whenEntriesWithinThreshold() {
        // Two labels 10 pt apart (centres). With 20 × 20 rects they overlap by 10 pt.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 110, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].landmarkIDs), Set(["A", "B"]))
    }

    func testCluster_atExactThresholdBoundary() {
        // 19 pt apart → rects overlap by 1 pt → cluster.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 119, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
    }

    func testNoCluster_atExactThreshold() {
        // 20 pt apart → rects just touch (no strict overlap) → no cluster.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 120, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertTrue(clusters.isEmpty)
    }

    func testThreeLabelCluster_allWithinThreshold() {
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 108, y: 200)),
            (id: "C", point: CGPoint(x: 105, y: 208)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].landmarkIDs.count, 3)
    }

    func testTransitiveClustering() {
        // A–B overlap, B–C overlap, A–C do NOT overlap directly.
        // Union-find still merges all three.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 115, y: 200)),  // 15 pt from A
            (id: "C", point: CGPoint(x: 130, y: 200)),  // 15 pt from B, 30 pt from A
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].landmarkIDs.count, 3)
    }

    func testTwoClusters_separateGroups() {
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 100)),
            (id: "B", point: CGPoint(x: 108, y: 100)),
            (id: "C", point: CGPoint(x: 400, y: 400)),
            (id: "D", point: CGPoint(x: 408, y: 400)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 2)
        let allIDs = Set(clusters.flatMap { $0.landmarkIDs })
        XCTAssertEqual(allIDs, Set(["A", "B", "C", "D"]))
    }

    func testSingleEntry_returnsNoClusters() {
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertTrue(clusters.isEmpty)
    }

    func testEmptyEntries_returnsNoClusters() {
        let clusters = ARLandmarkViewController.detectClusters(from: [])
        XCTAssertTrue(clusters.isEmpty)
    }

    func testClusterID_isDeterministic() {
        // Cluster ID must be the same regardless of entry order.
        let entriesAB: [(id: String, point: CGPoint)] = [
            (id: "Alpha", point: CGPoint(x: 100, y: 200)),
            (id: "Beta",  point: CGPoint(x: 108, y: 200)),
        ]
        let entriesBA: [(id: String, point: CGPoint)] = [
            (id: "Beta",  point: CGPoint(x: 108, y: 200)),
            (id: "Alpha", point: CGPoint(x: 100, y: 200)),
        ]
        let clustersAB = ARLandmarkViewController.detectClusters(from: entriesAB)
        let clustersBA = ARLandmarkViewController.detectClusters(from: entriesBA)
        XCTAssertEqual(clustersAB.first?.id, clustersBA.first?.id)
    }

    func testClusterCentre_isAverageOfMemberPositions() {
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 200)),
            (id: "B", point: CGPoint(x: 110, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.first?.screenCentre.x ?? 0, 105, accuracy: 0.01)
        XCTAssertEqual(clusters.first?.screenCentre.y ?? 0, 200, accuracy: 0.01)
    }

    func testSignificanceOrder_preservedInLandmarkIDs() {
        // Entry at index 0 (highest significance) should appear first in landmarkIDs.
        let entries: [(id: String, point: CGPoint)] = [
            (id: "High", point: CGPoint(x: 100, y: 200)),
            (id: "Low",  point: CGPoint(x: 108, y: 200)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.first?.landmarkIDs.first, "High")
    }

    // MARK: - Label-size parameter

    func testCluster_withActualLabelSize_overlappingLabels() {
        // Two labels 100 pt apart with 165-pt-wide rects → rects overlap by 65 pt → cluster.
        let labelSize = CGSize(width: 165, height: 70)
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 300)),
            (id: "B", point: CGPoint(x: 200, y: 300)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries, labelSize: labelSize)
        XCTAssertEqual(clusters.count, 1)
    }

    func testNoCluster_withActualLabelSize_nonOverlappingLabels() {
        // Two labels 200 pt apart with 165-pt-wide rects → no overlap → no cluster.
        let labelSize = CGSize(width: 165, height: 70)
        let entries: [(id: String, point: CGPoint)] = [
            (id: "A", point: CGPoint(x: 100, y: 300)),
            (id: "B", point: CGPoint(x: 300, y: 300)),
        ]
        let clusters = ARLandmarkViewController.detectClusters(from: entries, labelSize: labelSize)
        XCTAssertTrue(clusters.isEmpty)
    }

    // MARK: - Fan Position Calculation

    let viewSize = CGSize(width: 390, height: 844)   // iPhone 14 Pro logical points

    func testFanPositions_countMatchesInput() {
        for count in 1...7 {
            let centre = CGPoint(x: 195, y: 422)
            let positions = ARLandmarkViewController.fanPositions(count: count, centre: centre, in: viewSize)
            XCTAssertEqual(positions.count, count, "Expected \(count) positions")
        }
    }

    func testFanPositions_semicircle_labelsAreAboveCentre() {
        let centre = CGPoint(x: 195, y: 422)
        for count in 2...3 {
            let positions = ARLandmarkViewController.fanPositions(count: count, centre: centre, in: viewSize)
            for pos in positions {
                XCTAssertLessThanOrEqual(pos.y, centre.y + 1,
                    "All \(count)-label semicircle positions should be at or above centre")
            }
        }
    }

    func testFanPositions_allAtCorrectRadius() {
        let centre = CGPoint(x: 195, y: 422)
        let r = ARLandmarkViewController.fanRadius
        for count in [2, 3, 4, 6] {
            let positions = ARLandmarkViewController.fanPositions(count: count, centre: centre, in: viewSize)
            for pos in positions {
                let dist = hypot(pos.x - centre.x, pos.y - centre.y)
                XCTAssertEqual(dist, r, accuracy: 1.0,
                    "Position for count=\(count) should be ~\(r) pt from centre")
            }
        }
    }

    func testFanPositions_noOverlapBetweenItems() {
        let centre = CGPoint(x: 195, y: 422)
        for count in 2...6 {
            let positions = ARLandmarkViewController.fanPositions(count: count, centre: centre, in: viewSize)
            for i in 0..<positions.count {
                for j in (i + 1)..<positions.count {
                    let d = hypot(positions[i].x - positions[j].x,
                                  positions[i].y - positions[j].y)
                    XCTAssertGreaterThan(d, 40,
                        "Fan positions \(i) and \(j) for count=\(count) overlap too closely: \(d) pt")
                }
            }
        }
    }

    func testFanPositions_clampedWhenCentreNearTopEdge() {
        let centre = CGPoint(x: 195, y: 20)
        let positions = ARLandmarkViewController.fanPositions(count: 3, centre: centre, in: viewSize)
        for pos in positions {
            XCTAssertGreaterThanOrEqual(pos.y, 0, "No position should be above the screen")
        }
    }

    func testFanPositions_clampedWhenCentreNearLeftEdge() {
        let centre = CGPoint(x: 10, y: 422)
        let positions = ARLandmarkViewController.fanPositions(count: 4, centre: centre, in: viewSize)
        for pos in positions {
            XCTAssertGreaterThanOrEqual(pos.x, 0, "No position should be left of the screen")
        }
    }

    func testFanPositions_clampedWhenCentreNearRightEdge() {
        let centre = CGPoint(x: 380, y: 422)
        let positions = ARLandmarkViewController.fanPositions(count: 4, centre: centre, in: viewSize)
        for pos in positions {
            XCTAssertLessThanOrEqual(pos.x, viewSize.width, "No position should be right of the screen")
        }
    }

    // MARK: - Adjusted Centre

    func testAdjustedCentre_noShiftNeeded_whenPositionsFitOnScreen() {
        let centre = CGPoint(x: 200, y: 400)
        let positions = [CGPoint(x: 200, y: 320), CGPoint(x: 200, y: 480)]
        let adjusted = ARLandmarkViewController.adjustedCentre(centre, fanPositions: positions, in: viewSize)
        XCTAssertEqual(adjusted.x, centre.x, accuracy: 0.01)
        XCTAssertEqual(adjusted.y, centre.y, accuracy: 0.01)
    }

    func testAdjustedCentre_shiftsRightWhenPositionsOffLeftEdge() {
        let centre = CGPoint(x: 10, y: 422)
        let positions = [CGPoint(x: -80, y: 422), CGPoint(x: 90, y: 422)]
        let adjusted = ARLandmarkViewController.adjustedCentre(centre, fanPositions: positions, in: viewSize)
        XCTAssertGreaterThan(adjusted.x, centre.x, "Centre should shift right to keep positions on-screen")
    }

    // MARK: - Overflow Threshold

    func testMaxFanLabels_constant() {
        XCTAssertEqual(ARLandmarkViewController.maxFanLabels, 6)
    }

    func testCluster_withSevenLandmarks_producesOverflow() {
        let ids = (1...7).map { "L\($0)" }
        let entries: [(id: String, point: CGPoint)] = ids.enumerated().map { i, id in
            (id: id, point: CGPoint(x: 100 + CGFloat(i) * 2, y: 200))
        }
        let clusters = ARLandmarkViewController.detectClusters(from: entries)
        XCTAssertEqual(clusters.count, 1)
        let cluster = clusters[0]
        XCTAssertEqual(cluster.landmarkIDs.count, 7)
        let displayCount = min(cluster.landmarkIDs.count, ARLandmarkViewController.maxFanLabels)
        let overflowCount = cluster.landmarkIDs.count - displayCount
        XCTAssertEqual(displayCount, 6)
        XCTAssertEqual(overflowCount, 1)
    }
}
