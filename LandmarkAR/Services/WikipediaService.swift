import CoreLocation
import Foundation

// MARK: - WikipediaService
// Fetches nearby landmarks from the Wikipedia GeoSearch API,
// then loads a short summary for each one.

class WikipediaService {

    // MARK: - Fetch Nearby Landmarks

    /// Main entry point. Call this with the user's current location and the current settings.
    /// Returns an empty array immediately if Wikipedia is disabled in settings.
    func fetchNearbyLandmarks(near location: CLLocation, settings: AppSettings) async throws -> [Landmark] {

        // LAR-3: Respect the data source toggle
        guard settings.isWikipediaEnabled else { return [] }

        // LAR-4: Use the user's chosen distance as the search radius (convert km → meters)
        let radiusMeters = Int(settings.maxDistanceKm * 1000)
        let maxResults = 20

        // Step 1: Search for Wikipedia articles near this GPS coordinate
        let geoResults = try await geoSearch(near: location,
                                             radiusMeters: radiusMeters,
                                             maxResults: maxResults)

        // Step 2: For each result, fetch a short summary (run all fetches in parallel)
        let landmarks = try await withThrowingTaskGroup(of: Landmark?.self) { group in
            for result in geoResults {
                group.addTask {
                    try await self.buildLandmark(from: result, userLocation: location)
                }
            }

            var results: [Landmark] = []
            for try await landmark in group {
                if let landmark = landmark {
                    results.append(landmark)
                }
            }
            return results
        }

        // Sort by distance so the closest landmarks are first
        return landmarks.sorted { $0.distance < $1.distance }
    }

    // MARK: - Private Helpers

    /// Wikipedia GeoSearch: returns articles near a lat/lon
    private func geoSearch(near location: CLLocation,
                            radiusMeters: Int,
                            maxResults: Int) async throws -> [WikipediaGeoResult] {
        // Docs: https://www.mediawiki.org/wiki/API:Geosearch
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action",   value: "query"),
            URLQueryItem(name: "list",     value: "geosearch"),
            URLQueryItem(name: "gscoord",  value: "\(location.coordinate.latitude)|\(location.coordinate.longitude)"),
            URLQueryItem(name: "gsradius", value: "\(radiusMeters)"),
            URLQueryItem(name: "gslimit",  value: "\(maxResults)"),
            URLQueryItem(name: "format",   value: "json"),
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(WikipediaGeoSearchResponse.self, from: data)
        return response.query.geosearch
    }

    /// Fetches a plain-text summary for one Wikipedia article, then builds a Landmark
    private func buildLandmark(from result: WikipediaGeoResult, userLocation: CLLocation) async throws -> Landmark? {
        let urlString = "https://en.wikipedia.org/api/rest_v1/page/summary/\(result.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"

        guard let url = URL(string: urlString) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let summary = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)

        let landmarkLocation = CLLocation(latitude: result.lat, longitude: result.lon)
        let landmarkCoord = CLLocationCoordinate2D(latitude: result.lat, longitude: result.lon)

        let distance = userLocation.distance(from: landmarkLocation)
        let bearing  = userLocation.coordinate.bearing(to: landmarkCoord)
        let pageURL  = summary.content_urls?.desktop?.page.flatMap { URL(string: $0) }

        // LAR-5: Classify the landmark into a category
        let category = LandmarkCategory.classify(title: result.title, summary: summary.extract)

        return Landmark(
            id: "\(result.pageid)",
            title: result.title,
            summary: summary.extract,
            coordinate: landmarkCoord,
            wikipediaURL: pageURL,
            category: category,
            distance: distance,
            bearing: bearing
        )
    }
}

// MARK: - CLLocationCoordinate2D Bearing Extension

extension CLLocationCoordinate2D {
    /// Returns the bearing in degrees (0 = North, 90 = East, 180 = South, 270 = West)
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let fromLat = latitude.toRadians()
        let fromLon = longitude.toRadians()
        let toLat   = destination.latitude.toRadians()
        let toLon   = destination.longitude.toRadians()

        let dLon = toLon - fromLon
        let y = sin(dLon) * cos(toLat)
        let x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(dLon)

        let bearing = atan2(y, x).toDegrees()
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension Double {
    func toRadians() -> Double { self * .pi / 180 }
    func toDegrees() -> Double { self * 180 / .pi }
}
