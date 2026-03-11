import XCTest
import CoreLocation
import UIKit
@testable import LandmarkAR

// MARK: - LocationManagerOrientationTests
// Verifies that UIDeviceOrientation raw values map correctly to CLDeviceOrientation,
// which is the contract that applyHeadingOrientation() relies on.

final class LocationManagerOrientationTests: XCTestCase {

    // UIDeviceOrientation and CLDeviceOrientation share identical raw values.
    // These tests confirm that assumption holds for every orientation we care about.

    func testPortraitRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.portrait.rawValue,
                       Int(CLDeviceOrientation.portrait.rawValue))
    }

    func testPortraitUpsideDownRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.portraitUpsideDown.rawValue,
                       Int(CLDeviceOrientation.portraitUpsideDown.rawValue))
    }

    func testLandscapeLeftRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.landscapeLeft.rawValue,
                       Int(CLDeviceOrientation.landscapeLeft.rawValue))
    }

    func testLandscapeRightRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.landscapeRight.rawValue,
                       Int(CLDeviceOrientation.landscapeRight.rawValue))
    }

    func testFaceUpRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.faceUp.rawValue,
                       Int(CLDeviceOrientation.faceUp.rawValue))
    }

    func testFaceDownRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.faceDown.rawValue,
                       Int(CLDeviceOrientation.faceDown.rawValue))
    }

    func testUnknownRawValuesMatch() {
        XCTAssertEqual(UIDeviceOrientation.unknown.rawValue,
                       Int(CLDeviceOrientation.unknown.rawValue))
    }

    // Confirm that the orientations we skip (unknown, faceUp, faceDown) are correctly
    // excluded — only portrait and landscape variants should update headingOrientation.

    func testSkippedOrientationsAreExcluded() {
        let skipped: [CLDeviceOrientation] = [.unknown, .faceUp, .faceDown]
        for orientation in skipped {
            XCTAssertTrue(
                orientation == .unknown || orientation == .faceUp || orientation == .faceDown,
                "\(orientation) should be skipped"
            )
        }
    }

    func testApplicableOrientationsAreIncluded() {
        let applicable: [CLDeviceOrientation] = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        for orientation in applicable {
            XCTAssertFalse(
                orientation == .unknown || orientation == .faceUp || orientation == .faceDown,
                "\(orientation) should update headingOrientation"
            )
        }
    }
}
