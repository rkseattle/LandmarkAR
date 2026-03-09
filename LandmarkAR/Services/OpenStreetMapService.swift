import CoreLocation
import Foundation

// MARK: - OpenStreetMapService (LAR-11)
// Fetches nearby landmarks from the OpenStreetMap Overpass API.

class OpenStreetMapService {

    private let overpassURL = URL(string: "https://overpass-api.de/api/interpreter")!
    private let wikidataService = WikidataService()

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
    /// LAR-45: wikipediaService is passed in so Stage 3 GeoSearch can reuse the shared instance.
    func fetchNearbyLandmarks(near location: CLLocation,
                              settings: AppSettings,
                              wikipediaService: WikipediaService) async throws -> [Landmark] {

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
        // Overpass returns 400 for malformed queries, 429 for rate limiting, and
        // 5xx codes (503 overloaded, 504 gateway timeout) under heavy load — all
        // with non-JSON bodies that would cause a misleading format error.
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            // Transient server-side errors: return empty results silently so the
            // circuit breaker is not triggered. The next scheduled fetch will retry.
            let isTransient = http.statusCode == 429 || (http.statusCode >= 500 && http.statusCode < 600)
            if isTransient { return [] }
            throw URLError(.badServerResponse)
        }

        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

        // LAR-45: Resolve Wikipedia URLs for all elements concurrently.
        let languageCode = settings.appLanguage.rawValue
        let landmarks: [Landmark] = await withTaskGroup(of: Landmark?.self) { group in
            for element in (response.elements ?? []) {
                group.addTask {
                    guard let name = element.tags["name"],
                          let eLat = element.lat,
                          let eLon = element.lon else { return nil }

                    let coordinate    = CLLocationCoordinate2D(latitude: eLat, longitude: eLon)
                    let elementLocation = CLLocation(latitude: eLat, longitude: eLon)
                    let distance      = location.distance(from: elementLocation)
                    let bearing       = location.coordinate.bearing(to: coordinate)
                    let description   = element.tags["description"] ?? ""
                    let category      = LandmarkCategory.classify(title: name, summary: description)
                    let altitude      = element.tags["ele"].flatMap { Double($0) }  // LAR-15

                    // LAR-45: Run the 3-stage resolution pipeline for each element.
                    let wikiURL = await self.wikidataService.resolveWikipediaURL(
                        elementID: element.id,
                        tags: element.tags,
                        coordinate: coordinate,
                        languageCode: languageCode,
                        wikipediaService: wikipediaService
                    )

                    return Landmark(
                        id: "osm-\(element.id)",
                        title: name,
                        summary: description,
                        coordinate: coordinate,
                        wikipediaURL: wikiURL,
                        category: category,
                        distance: distance,
                        bearing: bearing,
                        altitude: altitude
                    )
                }
            }

            var results: [Landmark] = []
            for await landmark in group {
                if let l = landmark { results.append(l) }
            }
            return results
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
