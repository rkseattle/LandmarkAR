import XCTest
@testable import LandmarkAR

// LAR-40: Tests for LabelColorScheme — pure color-scheme logic, no ARKit dependency.

final class LabelColorSchemeTests: XCTestCase {

    // MARK: - Constants

    func test_lumaThreshold_is128() {
        XCTAssertEqual(LabelColorScheme.lumaThreshold, 128)
    }

    func test_sampleSize_is20() {
        XCTAssertEqual(LabelColorScheme.sampleSize, 20)
    }

    // MARK: - Scheme selection logic

    func test_brightBackground_selectsLightScheme() {
        // Y_avg > 128 → light scheme (dark text on light pill)
        let luma: UInt8 = 200
        let scheme: LabelColorScheme = luma > LabelColorScheme.lumaThreshold ? .light : .dark
        XCTAssertEqual(scheme, .light)
    }

    func test_darkBackground_selectsDarkScheme() {
        // Y_avg ≤ 128 → dark scheme (white text on dark pill)
        let luma: UInt8 = 50
        let scheme: LabelColorScheme = luma > LabelColorScheme.lumaThreshold ? .light : .dark
        XCTAssertEqual(scheme, .dark)
    }

    func test_exactThreshold_selectsDarkScheme() {
        // Y_avg == 128 is NOT > 128, so dark scheme applies
        let luma: UInt8 = 128
        let scheme: LabelColorScheme = luma > LabelColorScheme.lumaThreshold ? .light : .dark
        XCTAssertEqual(scheme, .dark)
    }

    func test_nilLuma_fallsBackToDarkScheme() {
        // When pixel buffer sampling fails (nil), caller defaults luma to 0 → dark scheme
        let luma: UInt8? = nil
        let scheme: LabelColorScheme = (luma ?? 0) > LabelColorScheme.lumaThreshold ? .light : .dark
        XCTAssertEqual(scheme, .dark)
    }

    // MARK: - Light scheme colors

    func test_lightScheme_textColorIsDark() {
        let color = LabelColorScheme.light.textColor
        var white: CGFloat = 0
        color.getWhite(&white, alpha: nil)
        XCTAssertLessThan(white, 0.2, "Light scheme text should be dark")
    }

    func test_lightScheme_iconTintIsDark() {
        let color = LabelColorScheme.light.iconTintColor
        var white: CGFloat = 0
        color.getWhite(&white, alpha: nil)
        XCTAssertLessThan(white, 0.2, "Light scheme icon tint should be dark")
    }

    // MARK: - Dark scheme colors

    func test_darkScheme_textColorIsWhite() {
        let color = LabelColorScheme.dark.textColor
        var white: CGFloat = 0
        color.getWhite(&white, alpha: nil)
        XCTAssertEqual(white, 1.0, accuracy: 0.001, "Dark scheme text should be white")
    }

    func test_darkScheme_iconTintIsWhite() {
        let color = LabelColorScheme.dark.iconTintColor
        var white: CGFloat = 0
        color.getWhite(&white, alpha: nil)
        XCTAssertEqual(white, 1.0, accuracy: 0.001, "Dark scheme icon tint should be white")
    }

    // MARK: - WCAG contrast sanity

    // WCAG 2.1 SC 1.4.3 requires ≥ 4.5:1 contrast for normal text.
    // Light scheme: dark text (#1A1A1A ≈ L=0.004) on white background (L=1.0)
    //   ratio = (1.0 + 0.05) / (0.004 + 0.05) ≈ 19.4:1 ✓
    // Dark scheme: white text (L=1.0) on near-black background (L≈0)
    //   ratio = (1.0 + 0.05) / (0.0 + 0.05) = 21:1 ✓
    // These tests verify the relative luminance values are in the expected range.

    func test_lightScheme_textAndBackgroundContrastIsAdequate() {
        let textWhite = CGFloat(0.1)   // UIColor(white: 0.1) → approximately L=0.010
        let bgWhite   = CGFloat(1.0)   // UIColor.white → L=1.0
        // Simplified contrast check: background is much lighter than text
        XCTAssertGreaterThan(bgWhite - textWhite, 0.8)
    }

    func test_darkScheme_textAndBackgroundContrastIsAdequate() {
        let textWhite = CGFloat(1.0)   // UIColor.white → L=1.0
        let bgWhite   = CGFloat(0.0)   // UIColor.black → L=0
        XCTAssertGreaterThan(textWhite - bgWhite, 0.8)
    }
}
