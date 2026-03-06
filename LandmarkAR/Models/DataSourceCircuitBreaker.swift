import Foundation

// MARK: - DataSourceCircuitBreaker (LAR-26)
// Tracks per-source consecutive failure counts. After `failureThreshold` failures
// a source is "open" (skipped) for `cooldownInterval` seconds, then auto-resets.
// Conforms to ObservableObject so it can be held as a @StateObject, but publishes
// no properties — circuit state is internal and does not need to drive view updates.

class DataSourceCircuitBreaker: ObservableObject {

    static let wikipedia     = "Wikipedia"
    static let openStreetMap = "OpenStreetMap"
    static let nps           = "National Park Service"

    private struct SourceState {
        var failureCount = 0
        var openUntil: Date? = nil
    }

    private var states: [String: SourceState] = [:]
    private let failureThreshold = 3
    private let cooldownInterval: TimeInterval = 300 // 5 minutes

    /// Returns true when the source is available (not in cooldown).
    func isAvailable(_ source: String) -> Bool {
        guard let openUntil = states[source]?.openUntil else { return true }
        if Date() >= openUntil {
            states[source] = SourceState() // cooldown expired — reset
            return true
        }
        return false
    }

    /// Call after a successful fetch to reset the failure count.
    func recordSuccess(_ source: String) {
        states[source] = SourceState()
    }

    /// Call after a failed fetch. Opens the circuit after `failureThreshold` failures.
    func recordFailure(_ source: String) {
        if states[source] == nil { states[source] = SourceState() }
        states[source]!.failureCount += 1
        if states[source]!.failureCount >= failureThreshold {
            states[source]!.openUntil = Date().addingTimeInterval(cooldownInterval)
        }
    }

    /// Minutes remaining in the cooldown, or nil if the source is available.
    func cooldownMinutesRemaining(_ source: String) -> Int? {
        guard let openUntil = states[source]?.openUntil, Date() < openUntil else { return nil }
        return max(1, Int(openUntil.timeIntervalSinceNow / 60))
    }
}
