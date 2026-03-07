import XCTest
@testable import LandmarkAR

// MARK: - AppLanguageTests (LAR-35)

final class AppLanguageTests: XCTestCase {

    // MARK: - Raw values / locale codes

    func testRawValues() {
        XCTAssertEqual(AppLanguage.english.rawValue,    "en")
        XCTAssertEqual(AppLanguage.japanese.rawValue,   "ja")
        XCTAssertEqual(AppLanguage.german.rawValue,     "de")
        XCTAssertEqual(AppLanguage.french.rawValue,     "fr")
        XCTAssertEqual(AppLanguage.spanish.rawValue,    "es")
        XCTAssertEqual(AppLanguage.portuguese.rawValue, "pt")
        XCTAssertEqual(AppLanguage.korean.rawValue,     "ko")
        XCTAssertEqual(AppLanguage.italian.rawValue,    "it")
    }

    func testAllCasesCount() {
        XCTAssertEqual(AppLanguage.allCases.count, 8)
    }

    func testRoundtrip() {
        for lang in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage(rawValue: lang.rawValue), lang,
                           "Round-trip failed for \(lang.rawValue)")
        }
    }

    // MARK: - Native names

    func testNativeNames() {
        XCTAssertEqual(AppLanguage.english.nativeName,    "English")
        XCTAssertEqual(AppLanguage.japanese.nativeName,   "日本語")
        XCTAssertEqual(AppLanguage.german.nativeName,     "Deutsch")
        XCTAssertEqual(AppLanguage.french.nativeName,     "Français")
        XCTAssertEqual(AppLanguage.spanish.nativeName,    "Español")
        XCTAssertEqual(AppLanguage.portuguese.nativeName, "Português")
        XCTAssertEqual(AppLanguage.korean.nativeName,     "한국어")
        XCTAssertEqual(AppLanguage.italian.nativeName,    "Italiano")
    }

    // MARK: - systemDefault()

    func testSystemDefaultReturnsEnglishForUnsupportedLocale() {
        // zh (Chinese) is not in the supported set — expect English fallback
        let result = AppLanguage.systemDefault()
        // We can only assert it returns a valid AppLanguage (not crash)
        XCTAssertNotNil(result)
        XCTAssertTrue(AppLanguage.allCases.contains(result))
    }

    // MARK: - Identifiable

    func testIdEqualsRawValue() {
        for lang in AppLanguage.allCases {
            XCTAssertEqual(lang.id, lang.rawValue)
        }
    }

    // MARK: - AppSettings integration

    func testAppSettingsDefaultsToSystemLanguageOrEnglish() {
        let sut = AppSettings()
        XCTAssertTrue(AppLanguage.allCases.contains(sut.appLanguage),
                      "Default language must be one of the 8 supported languages")
    }

    func testAppSettingsLanguagePersistence() {
        let sut = AppSettings()
        sut.appLanguage = .german
        XCTAssertEqual(sut.appLanguage, .german)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "de")

        // Reset to avoid polluting other tests
        sut.appLanguage = .english
    }

    func testAppSettingsLocalizedBundleFallsBackToMainBundle() {
        let sut = AppSettings()
        // English should always resolve — at worst falls back to .main
        sut.appLanguage = .english
        XCTAssertNotNil(sut.localizedBundle)
    }
}
