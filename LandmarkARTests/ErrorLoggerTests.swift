import XCTest
@testable import LandmarkAR

final class ErrorLoggerTests: XCTestCase {

    var sut: ErrorLogger!

    // Use a test-only key so tests don't pollute or read real app data.
    private let testKey = "errorLogEntries"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        sut = ErrorLogger()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    // MARK: - Initial state

    func testStartsEmpty() {
        XCTAssertTrue(sut.entries.isEmpty)
    }

    // MARK: - log(_:)

    func testLogAddsEntry() {
        sut.log("Something went wrong")

        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].message, "Something went wrong")
    }

    func testLogPreservesOrder() {
        sut.log("first")
        sut.log("second")
        sut.log("third")

        XCTAssertEqual(sut.entries.map(\.message), ["first", "second", "third"])
    }

    func testLogSetsDate() {
        let before = Date()
        sut.log("timed event")
        let after = Date()

        XCTAssertGreaterThanOrEqual(sut.entries[0].date, before)
        XCTAssertLessThanOrEqual(sut.entries[0].date, after)
    }

    func testMultipleLogsIncrementCount() {
        for i in 1...5 {
            sut.log("error \(i)")
        }
        XCTAssertEqual(sut.entries.count, 5)
    }

    // MARK: - clear()

    func testClearRemovesAllEntries() {
        sut.log("a")
        sut.log("b")
        sut.clear()

        XCTAssertTrue(sut.entries.isEmpty)
    }

    func testClearOnEmptyLoggerIsNoop() {
        sut.clear()
        XCTAssertTrue(sut.entries.isEmpty)
    }

    func testCanLogAfterClear() {
        sut.log("before")
        sut.clear()
        sut.log("after")

        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].message, "after")
    }

    // MARK: - Entry identity

    func testEachEntryHasUniqueID() {
        sut.log("x")
        sut.log("y")

        XCTAssertNotEqual(sut.entries[0].id, sut.entries[1].id)
    }

    func testEmptyMessageIsAccepted() {
        sut.log("")
        XCTAssertEqual(sut.entries.count, 1)
        XCTAssertEqual(sut.entries[0].message, "")
    }

    // MARK: - Persistence (LAR-32)

    func testEntriesPersistedAcrossInstances() {
        sut.log("persisted error")
        sut.log("another error")

        let reloaded = ErrorLogger()
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.map(\.message), ["persisted error", "another error"])
    }

    func testClearAlsoClearsPersistence() {
        sut.log("will be cleared")
        sut.clear()

        let reloaded = ErrorLogger()
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    func testEntriesRestoredWithCorrectDates() {
        let before = Date()
        sut.log("dated entry")
        let after = Date()

        let reloaded = ErrorLogger()
        XCTAssertGreaterThanOrEqual(reloaded.entries[0].date, before)
        XCTAssertLessThanOrEqual(reloaded.entries[0].date, after)
    }

    func testMaxEntriesCapAt200() {
        for i in 1...205 {
            sut.log("error \(i)")
        }
        XCTAssertEqual(sut.entries.count, 200)
        // Oldest entries are dropped; newest remain
        XCTAssertEqual(sut.entries.last?.message, "error 205")
    }
}
