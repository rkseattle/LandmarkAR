import CoreLocation
import Foundation

// MARK: - WikipediaService
// Fetches nearby landmarks from the Wikipedia GeoSearch API,
// then loads a short summary for each one.

class WikipediaService {

    // URLSession with a short request timeout — prevents hanging for the default 60 s.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // In-memory response cache. Key: "lat,lon,radius,lang" (coordinates rounded to 3 dp ≈ 100 m).
    // NSCache evicts automatically under memory pressure.
    private let cache = NSCache<NSString, CacheBox>()

    private class CacheBox: NSObject {
        let landmarks: [Landmark]
        init(_ landmarks: [Landmark]) { self.landmarks = landmarks }
    }

    private func cacheKey(lat: Double, lon: Double, radius: Int, lang: String) -> NSString {
        let rLat = (lat * 1000).rounded() / 1000
        let rLon = (lon * 1000).rounded() / 1000
        return "\(rLat),\(rLon),\(radius),\(lang)" as NSString
    }

    // MARK: - Fetch Nearby Landmarks

    /// Main entry point. Call this with the user's current location and the current settings.
    /// Returns an empty array immediately if Wikipedia is disabled in settings.
    func fetchNearbyLandmarks(near location: CLLocation, settings: AppSettings) async throws -> [Landmark] {

        // LAR-3: Respect the data source toggle
        guard settings.isWikipediaEnabled else { return [] }

        // LAR-4: Use the user's chosen distance as the search radius (convert km → meters).
        // Wikipedia GeoSearch caps gsradius at 10,000 m; clamp to avoid API errors.
        let radiusMeters = min(Int(settings.maxDistanceKm * 1000), 10_000)
        let maxResults = 20

        // LAR-35: Capture the language code once so both steps use the same value.
        let languageCode = settings.appLanguage.rawValue

        // Return cached results when the user hasn't moved far enough to cross a cell boundary.
        let key = cacheKey(lat: location.coordinate.latitude,
                           lon: location.coordinate.longitude,
                           radius: radiusMeters,
                           lang: languageCode)
        if let cached = cache.object(forKey: key) {
            return cached.landmarks
        }

        // Step 1: Search for Wikipedia articles near this GPS coordinate
        let geoResults = try await geoSearch(near: location,
                                             radiusMeters: radiusMeters,
                                             maxResults: maxResults,
                                             languageCode: languageCode)

        // Step 2: For each result, fetch a short summary (run all fetches in parallel).
        // Individual article failures are non-fatal — a bad page is skipped rather than
        // aborting the entire fetch.
        let landmarks = await withTaskGroup(of: Landmark?.self) { group in
            for result in geoResults {
                group.addTask {
                    await self.buildLandmark(from: result, userLocation: location, languageCode: languageCode)
                }
            }

            var results: [Landmark] = []
            for await landmark in group {
                if let landmark = landmark {
                    results.append(landmark)
                }
            }
            return results
        }

        // Sort by distance so the closest landmarks are first
        let sorted = landmarks.sorted { $0.distance < $1.distance }
        cache.setObject(CacheBox(sorted), forKey: key)
        return sorted
    }

    // MARK: - Private Helpers

    /// Wikipedia GeoSearch: returns articles near a lat/lon
    private func geoSearch(near location: CLLocation,
                            radiusMeters: Int,
                            maxResults: Int,
                            languageCode: String) async throws -> [WikipediaGeoResult] {
        // Docs: https://www.mediawiki.org/wiki/API:Geosearch
        // LAR-35: Use the language subdomain from settings (e.g. ja.wikipedia.org)
        var components = URLComponents(string: "https://\(languageCode).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action",   value: "query"),
            URLQueryItem(name: "list",     value: "geosearch"),
            URLQueryItem(name: "gscoord",  value: "\(location.coordinate.latitude)|\(location.coordinate.longitude)"),
            URLQueryItem(name: "gsradius", value: "\(radiusMeters)"),
            URLQueryItem(name: "gslimit",  value: "\(maxResults)"),
            URLQueryItem(name: "format",   value: "json"),
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(WikipediaGeoSearchResponse.self, from: data)
        return response.query.geosearch
    }

    /// Fetches a plain-text summary for one Wikipedia article, then builds a Landmark.
    /// Returns nil (rather than throwing) if the page is missing or the response is malformed.
    private func buildLandmark(from result: WikipediaGeoResult,
                                userLocation: CLLocation,
                                languageCode: String) async -> Landmark? {
        // LAR-35: Use the language subdomain from settings
        let urlString = "https://\(languageCode).wikipedia.org/api/rest_v1/page/summary/\(result.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let summary = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)

            let landmarkLocation = CLLocation(latitude: result.lat, longitude: result.lon)
            let landmarkCoord = CLLocationCoordinate2D(latitude: result.lat, longitude: result.lon)

            let distance = userLocation.distance(from: landmarkLocation)
            let bearing  = userLocation.coordinate.bearing(to: landmarkCoord)
            let pageURL  = summary.content_urls?.desktop?.page.flatMap { URL(string: $0) }
            let extract  = summary.extract ?? ""

            // LAR-5: Classify the landmark into a category
            let category = LandmarkCategory.classify(title: result.title, summary: extract)

            return Landmark(
                id: "\(result.pageid)",
                title: result.title,
                summary: extract,
                coordinate: landmarkCoord,
                wikipediaURL: pageURL,
                category: category,
                distance: distance,
                bearing: bearing
            )
        } catch {
            return nil
        }
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
