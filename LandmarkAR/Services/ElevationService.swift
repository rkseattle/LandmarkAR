import Foundation

// MARK: - ElevationService (LAR-15)
// Fetches terrain elevation for landmarks using the Open-Elevation public API.
// Landmarks that already have altitude from their data source (e.g. OSM's `ele` tag)
// are skipped. Falls back silently on failure — AR placement degrades to y = 0.

class ElevationService {

    private let endpoint = URL(string: "https://api.open-elevation.com/api/v1/lookup")!

    /// Fetches elevations for all landmarks in `landmarks` whose altitude is nil.
    /// Returns a dictionary mapping landmark ID → altitude in metres above sea level.
    func fetchElevations(for landmarks: [Landmark]) async -> [String: Double] {
        let needsElevation = landmarks.filter { $0.altitude == nil }
        guard !needsElevation.isEmpty else { return [:] }

        let locations = needsElevation.map { [
            "latitude":  $0.coordinate.latitude,
            "longitude": $0.coordinate.longitude
        ] }

        guard let body = try? JSONSerialization.data(withJSONObject: ["locations": locations]) else {
            return [:]
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(ElevationResponse.self, from: data) else {
            return [:]
        }

        var result: [String: Double] = [:]
        for (index, entry) in response.results.enumerated() where index < needsElevation.count {
            result[needsElevation[index].id] = entry.elevation
        }
        return result
    }
}

// MARK: - Response Models

private struct ElevationResponse: Codable {
    let results: [ElevationResult]
}

private struct ElevationResult: Codable {
    let latitude: Double
    let longitude: Double
    let elevation: Double
}
