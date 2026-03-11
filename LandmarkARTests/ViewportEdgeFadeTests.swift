import XCTest
import CoreLocation
@testable import LandmarkAR

// MARK: - ViewportEdgeFadeTests
// Unit tests for LAR-48 edge fade opacity logic in ARLandmarkViewController.

final class ViewportEdgeFadeTests: XCTestCase {

    private let viewSize = CGSize(width: 390, height: 844) // iPhone 14 portrait

    // MARK: - edgeFadeOpacity

    func testFullOpacityAtCenter() {
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: center, in: viewSize)
        XCTAssertEqual(opacity, 1.0, accuracy: 0.001)
    }

    func testZeroOpacityAtEdge() {
        // Exactly at the left edge (x=0) — well inside edgeInset → should be 0
        let point = CGPoint(x: 0, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testZeroOpacityAtEdgeInset() {
        // At exactly edgeInset from left edge — should still be 0 (boundary of fade zone)
        let point = CGPoint(x: ARLandmarkViewController.edgeInset, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testFullOpacityBeyondFadeZone() {
        // edgeInset + fadeZoneWidth from left edge — should be 1.0
        let x = ARLandmarkViewController.edgeInset + ARLandmarkViewController.fadeZoneWidth
        let point = CGPoint(x: x, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 1.0, accuracy: 0.001)
    }

    func testHalfOpacityAtMidFadeZone() {
        // Midpoint of fade zone from left edge
        let x = ARLandmarkViewController.edgeInset + ARLandmarkViewController.fadeZoneWidth / 2
        let point = CGPoint(x: x, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.5, accuracy: 0.01)
    }

    func testTopEdgeFade() {
        let point = CGPoint(x: viewSize.width / 2, y: ARLandmarkViewController.edgeInset / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testBottomEdgeFade() {
        let y = viewSize.height - ARLandmarkViewController.edgeInset / 2
        let point = CGPoint(x: viewSize.width / 2, y: y)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testRightEdgeFade() {
        let x = viewSize.width - ARLandmarkViewController.edgeInset / 2
        let point = CGPoint(x: x, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testOpacityIsClampedToZeroForNegativeInput() {
        // Point outside the viewport (negative x)
        let point = CGPoint(x: -10, y: viewSize.height / 2)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertEqual(opacity, 0.0, accuracy: 0.001)
    }

    func testOpacityIsClampedToOneMax() {
        // Well inside viewport — should never exceed 1.0
        let point = CGPoint(x: 200, y: 400)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: point, in: viewSize)
        XCTAssertLessThanOrEqual(opacity, 1.0)
    }

    // MARK: - Constants

    func testEdgeInsetMatchesLegacyValue() {
        // LAR-42 used edgeInset=75; LAR-48 promotes it to a named constant — value unchanged.
        XCTAssertEqual(ARLandmarkViewController.edgeInset, 75)
    }

    func testFadeZoneWidthIsPositive() {
        XCTAssertGreaterThan(ARLandmarkViewController.fadeZoneWidth, 0)
    }

    // MARK: - Symmetry

    func testLeftAndRightSymmetry() {
        let yMid = viewSize.height / 2
        let xLeft = ARLandmarkViewController.edgeInset + 20
        let xRight = viewSize.width - ARLandmarkViewController.edgeInset - 20
        let leftOpacity  = ARLandmarkViewController.edgeFadeOpacity(at: CGPoint(x: xLeft,  y: yMid), in: viewSize)
        let rightOpacity = ARLandmarkViewController.edgeFadeOpacity(at: CGPoint(x: xRight, y: yMid), in: viewSize)
        XCTAssertEqual(leftOpacity, rightOpacity, accuracy: 0.001)
    }

    func testTopAndBottomSymmetry() {
        let xMid = viewSize.width / 2
        let yTop    = ARLandmarkViewController.edgeInset + 20
        let yBottom = viewSize.height - ARLandmarkViewController.edgeInset - 20
        let topOpacity    = ARLandmarkViewController.edgeFadeOpacity(at: CGPoint(x: xMid, y: yTop),    in: viewSize)
        let bottomOpacity = ARLandmarkViewController.edgeFadeOpacity(at: CGPoint(x: xMid, y: yBottom), in: viewSize)
        XCTAssertEqual(topOpacity, bottomOpacity, accuracy: 0.001)
    }

    // MARK: - Corner

    func testCornerUsesNearestEdge() {
        // At the corner, both x and y distances are small — the minimum of the two governs.
        let corner = CGPoint(x: ARLandmarkViewController.edgeInset + 10,
                             y: ARLandmarkViewController.edgeInset + 10)
        let opacity = ARLandmarkViewController.edgeFadeOpacity(at: corner, in: viewSize)
        let expected = 10 / ARLandmarkViewController.fadeZoneWidth
        XCTAssertEqual(opacity, expected, accuracy: 0.01)
    }
}
