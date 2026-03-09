import XCTest
@testable import LandmarkAR

final class DataSourceCircuitBreakerTests: XCTestCase {

    var sut: DataSourceCircuitBreaker!
    let src = DataSourceCircuitBreaker.wikipedia

    override func setUp() {
        super.setUp()
        sut = DataSourceCircuitBreaker()
    }

    // MARK: - Initial state

    func testNewSourceIsAvailable() {
        XCTAssertTrue(sut.isAvailable(src))
    }

    func testCooldownMinutesRemainingNilWhenAvailable() {
        XCTAssertNil(sut.cooldownMinutesRemaining(src))
    }

    // MARK: - Failure threshold

    func testOneFailureStillAvailable() {
        sut.recordFailure(src)
        XCTAssertTrue(sut.isAvailable(src))
    }

    func testTwoFailuresStillAvailable() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        XCTAssertTrue(sut.isAvailable(src))
    }

    func testThreeFailuresOpensCircuit() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordFailure(src)
        XCTAssertFalse(sut.isAvailable(src))
    }

    // MARK: - Cooldown

    func testCooldownMinutesRemainingAfterCircuitOpens() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordFailure(src)

        let mins = sut.cooldownMinutesRemaining(src)
        XCTAssertNotNil(mins)
        XCTAssertGreaterThan(mins!, 0)
        XCTAssertLessThanOrEqual(mins!, 5)  // cooldown is 300 s = 5 min
    }

    // MARK: - Success resets state

    func testSuccessResetsFailureCount() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordSuccess(src)

        // Two more failures after reset should not open the circuit
        sut.recordFailure(src)
        sut.recordFailure(src)
        XCTAssertTrue(sut.isAvailable(src))
    }

    func testSuccessAfterOpenResetsCircuit() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordFailure(src)
        XCTAssertFalse(sut.isAvailable(src))

        sut.recordSuccess(src)
        XCTAssertTrue(sut.isAvailable(src))
        XCTAssertNil(sut.cooldownMinutesRemaining(src))
    }

    func testCooldownNilAfterSuccessReset() {
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordSuccess(src)
        XCTAssertNil(sut.cooldownMinutesRemaining(src))
    }

    // MARK: - Source isolation

    func testDifferentSourcesAreIndependent() {
        let osm = DataSourceCircuitBreaker.openStreetMap

        sut.recordFailure(src)
        sut.recordFailure(src)
        sut.recordFailure(src)

        XCTAssertFalse(sut.isAvailable(src))
        XCTAssertTrue(sut.isAvailable(osm))
    }

    func testAllSourcesCanOpenIndependently() {
        [DataSourceCircuitBreaker.wikipedia,
         DataSourceCircuitBreaker.openStreetMap].forEach { source in
            for _ in 0..<3 { sut.recordFailure(source) }
            XCTAssertFalse(sut.isAvailable(source), "\(source) should be open")
        }
    }

    // MARK: - Static constants

    func testStaticSourceNames() {
        XCTAssertEqual(DataSourceCircuitBreaker.wikipedia,     "Wikipedia")
        XCTAssertEqual(DataSourceCircuitBreaker.openStreetMap, "OpenStreetMap")
    }
}
