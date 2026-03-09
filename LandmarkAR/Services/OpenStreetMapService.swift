import CoreLocation
import Foundation

// MARK: - OpenStreetMapService (LAR-11)
// Fetches nearby landmarks from the OpenStreetMap Overpass API.

class OpenStreetMapService {

    private let overpassURL = URL(string: "https://overpass-api.de/api/interpreter")!

    // In-memory cache: key "lat,lon,radius" (coordinates rounded to 3 dp ≈ 100 m).
    private let cache = NSCache<NSString, CacheBox>()

    private class CacheBox: NSObject {
        let landmarks: [Landmark]
        init(_ landmarks: [Landmark]) { self.landmarks = landmarks }
    }

    private func cacheKey(lat: Double, lon: Double, radius: Int) -> NSString {
        let rLat = (lat * 1000).rounded() / 1000
        let rLon = (lon * 1000).rounded() / 1000
        return "\(rLat),\(rLon),\(radius)" as NSString
    }

    // MARK: - Fetch Nearby Landmarks

    /// Main entry point. Returns an empty array immediately if OSM is disabled in settings.
    /// Throws on network or decode failure so the caller can record a circuit-breaker strike.
    func fetchNearbyLandmarks(near location: CLLocation, settings: AppSettings) async throws -> [Landmark] {

        // LAR-11: Respect the data source toggle
        guard settings.isOpenStreetMapEnabled else { return [] }

        let radiusMeters = Int(settings.maxDistanceKm * 1000)
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let key = cacheKey(lat: lat, lon: lon, radius: radiusMeters)
        if let cached = cache.object(forKey: key) {
            return cached.landmarks
        }

        // Overpass QL query: fetch tourism, historic, and natural nodes within the radius
        let query = """
        [out:json][timeout:25];
        (
          node["tourism"~"attraction|museum|viewpoint|monument|artwork"](around:\(radiusMeters),\(lat),\(lon));
          node["historic"~"monument|memorial|ruins|castle|building|archaeological_site"](around:\(radiusMeters),\(lat),\(lon));
          node["natural"~"peak|waterfall|cave_entrance|beach|volcano"](around:\(radiusMeters),\(lat),\(lon));
        );
        out body;
        """

        // LAR-44: Request timeout must exceed the Overpass query timeout (25 s) so the
        // server can finish and return a well-formed response rather than timing out first.
        var request = URLRequest(url: overpassURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, urlResponse) = try await URLSession.shared.data(for: request)

        // LAR-44: Reject non-200 responses before attempting JSON decoding.
        // Overpass returns 400 for malformed queries and 429 for rate limiting,
        // both with non-JSON bodies that would cause a misleading format error.
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            // HTTP 429 means Overpass is rate-limiting this client. Return empty results
            // silently so the circuit breaker is not triggered — the next scheduled fetch
            // will retry naturally without a 4-minute pause.
            if http.statusCode == 429 {
                return []
            }
            throw URLError(.badServerResponse)
        }

        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

        let landmarks: [Landmark] = (response.elements ?? []).compactMap { element in
            guard let name = element.tags["name"],
                  let lat = element.lat,
                  let lon = element.lon else { return nil }

            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let elementLocation = CLLocation(latitude: lat, longitude: lon)
            let distance = location.distance(from: elementLocation)
            let bearing = location.coordinate.bearing(to: coordinate)
            let description = element.tags["description"] ?? ""
            let category = LandmarkCategory.classify(title: name, summary: description)
            let altitude = element.tags["ele"].flatMap { Double($0) }  // LAR-15

            return Landmark(
                id: "osm-\(element.id)",
                title: name,
                summary: description,
                coordinate: coordinate,
                wikipediaURL: nil,
                category: category,
                distance: distance,
                bearing: bearing,
                altitude: altitude
            )
        }

        let sorted = landmarks.sorted { $0.distance < $1.distance }
        cache.setObject(CacheBox(sorted), forKey: key)
        return sorted
    }
}

// MARK: - Overpass API Response Models

private struct OverpassResponse: Codable {
    // LAR-44: elements is optional — Overpass error envelopes may omit it entirely,
    // containing only a "remark" field. Treat a missing/empty elements list as zero results.
    let elements: [OverpassElement]?
}

private struct OverpassElement: Codable {
    let id: Int
    let lat: Double?
    let lon: Double?
    let tags: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        tags = (try container.decodeIfPresent([String: String].self, forKey: .tags)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, tags
    }
}
