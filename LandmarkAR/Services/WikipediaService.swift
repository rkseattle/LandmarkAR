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

    // LAR-39: Per-title pageview cache for the session lifetime.
    // Avoids redundant API calls when the user moves slightly and results overlap.
    private let pageviewCache = NSCache<NSString, PageviewBox>()

    private class PageviewBox: NSObject {
        let views: Int
        init(_ views: Int) { self.views = views }
    }

    // MARK: - LAR-46: Fetch Pool Size

    /// Number of candidates fetched from the Wikipedia GeoSearch API.
    /// Larger than `ARLandmarkViewController.maxVisibleLabels` so off-screen landmarks
    /// don't starve the visible arc of results.
    static let geoSearchLimit = 50

    // MARK: - LAR-39: Significance Scoring Constants

    /// Minimum monthly pageview count to pass the default significance filter.
    /// LAR-47: Lowered from 1,000 to 500 — the 1,000 threshold was too aggressive
    /// for dense urban areas where locally notable landmarks fall below the previous cutoff.
    static let minPageviewThreshold = 500

    /// Monthly pageview count required when "Iconic Landmarks Only" is enabled.
    static let iconicPageviewThreshold = 10_000

    /// Extract character count used to normalize the article-length signal to [0, 1].
    static let maxExtractLengthForNormalization = 2_000

    /// Composite significance score: pageviews (primary) + normalized article length (secondary).
    /// A nil pageview count means the API call failed; fall back to article-length-only scoring.
    static func significanceScore(pageviews: Int?, extractLength: Int) -> Double {
        let normalizedLength = min(Double(extractLength) / Double(maxExtractLengthForNormalization), 1.0)
        let views = Double(pageviews ?? 0)
        return views * 0.8 + normalizedLength * 0.2
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
                                             maxResults: WikipediaService.geoSearchLimit,
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

        // LAR-39: Apply significance threshold filtering.
        // Landmarks where the pageviews fetch failed (pageviews == nil) are kept as-is
        // per the fallback requirement; only landmarks with a known low view count are dropped.
        let threshold = settings.isIconicLandmarksOnly
            ? WikipediaService.iconicPageviewThreshold
            : WikipediaService.minPageviewThreshold
        let filtered = landmarks.filter { landmark in
            guard let views = landmark.pageviews else { return true }
            return views >= threshold
        }

        // Sort by significance descending so the highest-priority landmarks are first.
        // Distance is a tiebreaker to maintain stable ordering for equal scores.
        let sorted = filtered.sorted {
            if $0.significanceScore != $1.significanceScore {
                return $0.significanceScore > $1.significanceScore
            }
            return $0.distance < $1.distance
        }
        cache.setObject(CacheBox(sorted), forKey: key)
        return sorted
    }

    // MARK: - Stage 3 Cross-Reference (LAR-45)

    /// Returns the Wikipedia URL of the closest article within 50 m of the given
    /// coordinate, or nil if none is found. Used as the last-resort stage in the
    /// OSM Wikipedia link resolution pipeline.
    func closestWikipediaURL(near location: CLLocation, languageCode: String) async -> URL? {
        guard let results = try? await geoSearch(near: location,
                                                 radiusMeters: 50,
                                                 maxResults: 1,
                                                 languageCode: languageCode),
              let first = results.first,
              first.dist <= 50 else { return nil }
        let encoded = first.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? first.title
        return URL(string: "https://\(languageCode).wikipedia.org/wiki/\(encoded)")
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
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "geosearch"),
            URLQueryItem(name: "gscoord",     value: "\(location.coordinate.latitude)|\(location.coordinate.longitude)"),
            URLQueryItem(name: "gsradius",    value: "\(radiusMeters)"),
            URLQueryItem(name: "gslimit",     value: "\(maxResults)"),
            // LAR-47: Explicitly pin to namespace 0 (main articles) to ensure consistent
            // result counts across API configurations and prevent deprioritisation of
            // articles without coordinates properties.
            URLQueryItem(name: "gsnamespace", value: "0"),
            URLQueryItem(name: "format",      value: "json"),
        ]

        let (data, urlResponse) = try await session.data(from: components.url!)

        // Reject non-200 responses before attempting JSON decoding — same pattern as LAR-44.
        // Wikipedia returns 429 for rate limiting and 5xx for transient server errors, both
        // with non-JSON bodies that would otherwise produce a misleading format error.
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            let isTransient = http.statusCode == 429 || (http.statusCode >= 500 && http.statusCode < 600)
            if isTransient { return [] }
            throw URLError(.badServerResponse)
        }

        let response = try JSONDecoder().decode(WikipediaGeoSearchResponse.self, from: data)
        return response.query.geosearch
    }

    /// Fetches a plain-text summary for one Wikipedia article, then builds a Landmark.
    /// Also fetches monthly pageview count in parallel to compute a significance score.
    /// Returns nil (rather than throwing) if the page is missing or the response is malformed.
    private func buildLandmark(from result: WikipediaGeoResult,
                                userLocation: CLLocation,
                                languageCode: String) async -> Landmark? {
        // LAR-35: Use the language subdomain from settings
        let encodedTitle = result.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let summaryURLString = "https://\(languageCode).wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)"
        guard let summaryURL = URL(string: summaryURLString) else { return nil }

        do {
            // LAR-39: Fetch summary and pageviews in parallel to avoid sequential latency.
            async let summaryFetch = session.data(from: summaryURL)
            async let pageviewsFetch = fetchPageviews(title: result.title, languageCode: languageCode)

            let (data, _) = try await summaryFetch
            let summary = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
            let views = await pageviewsFetch

            let landmarkLocation = CLLocation(latitude: result.lat, longitude: result.lon)
            let landmarkCoord = CLLocationCoordinate2D(latitude: result.lat, longitude: result.lon)

            let distance = userLocation.distance(from: landmarkLocation)
            let bearing  = userLocation.coordinate.bearing(to: landmarkCoord)
            let pageURL  = summary.content_urls?.desktop?.page.flatMap { URL(string: $0) }
            let extract  = summary.extract ?? ""

            // LAR-5: Classify the landmark into a category
            let category = LandmarkCategory.classify(title: result.title, summary: extract)

            // LAR-39: Compute composite significance score
            let score = WikipediaService.significanceScore(pageviews: views, extractLength: extract.count)

            return Landmark(
                id: "\(result.pageid)",
                title: result.title,
                summary: extract,
                coordinate: landmarkCoord,
                wikipediaURL: pageURL,
                category: category,
                distance: distance,
                bearing: bearing,
                significanceScore: score,
                pageviews: views
            )
        } catch {
            return nil
        }
    }

    /// Fetches the 30-day view count for a Wikipedia article from the Wikimedia pageviews API.
    /// Returns nil on any network or decode failure (caller keeps the landmark via fallback scoring).
    /// Results are cached per title for the session lifetime.
    private func fetchPageviews(title: String, languageCode: String) async -> Int? {
        let cacheKey = "\(languageCode):\(title)" as NSString
        if let cached = pageviewCache.object(forKey: cacheKey) {
            return cached.views
        }

        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let timestamp = currentMonthTimestamp()
        let urlString = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/\(languageCode).wikipedia.org/all-access/all-agents/\(encodedTitle)/monthly/\(timestamp)/\(timestamp)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(WikipediaPageviewsResponse.self, from: data)
            let views = response.items.first?.views
            if let views = views {
                pageviewCache.setObject(PageviewBox(views), forKey: cacheKey)
            }
            return views
        } catch {
            return nil
        }
    }

    /// Returns the current month as a Wikimedia pageviews timestamp (e.g. "20240101").
    private func currentMonthTimestamp() -> String {
        let calendar = Calendar.current
        let now = Date()
        let year  = calendar.component(.year,  from: now)
        let month = calendar.component(.month, from: now)
        return String(format: "%04d%02d01", year, month)
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
