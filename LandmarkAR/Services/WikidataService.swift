import CoreLocation
import Foundation

// MARK: - WikidataService (LAR-45)
// Resolves Wikipedia URLs for OSM landmarks via a 3-stage fallback pipeline:
//   Stage 1 — parse the OSM `wikipedia` tag directly (no network call)
//   Stage 2 — query the Wikidata sitelinks API using the OSM `wikidata` tag
//   Stage 3 — Wikipedia GeoSearch cross-reference within 50 m (last resort)
// Results are cached per OSM element ID so repeat fetches skip redundant API calls.

class WikidataService {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    // Cache per OSM element ID. URLBox.url == nil means all stages failed.
    private let urlCache = NSCache<NSString, URLBox>()

    private class URLBox: NSObject {
        let url: URL?
        init(_ url: URL?) { self.url = url }
    }

    // MARK: - Public API

    /// Resolves a Wikipedia URL for an OSM element using a 3-stage fallback pipeline.
    /// Cached per element ID — subsequent calls for the same element return immediately.
    func resolveWikipediaURL(elementID: Int,
                             tags: [String: String],
                             coordinate: CLLocationCoordinate2D,
                             languageCode: String,
                             wikipediaService: WikipediaService) async -> URL? {
        let key = "\(elementID)" as NSString
        if let cached = urlCache.object(forKey: key) {
            return cached.url
        }

        let resolved = await resolvePipeline(tags: tags,
                                             coordinate: coordinate,
                                             languageCode: languageCode,
                                             wikipediaService: wikipediaService)
        urlCache.setObject(URLBox(resolved), forKey: key)
        return resolved
    }

    // MARK: - Resolution Pipeline

    private func resolvePipeline(tags: [String: String],
                                 coordinate: CLLocationCoordinate2D,
                                 languageCode: String,
                                 wikipediaService: WikipediaService) async -> URL? {
        // Stage 1: OSM wikipedia tag — no network call needed.
        if let url = resolveFromWikipediaTag(tags["wikipedia"]) {
            return url
        }

        // Stage 2: OSM wikidata tag → Wikidata sitelinks API.
        if let wikidataID = tags["wikidata"],
           let url = await resolveFromWikidata(id: wikidataID, languageCode: languageCode) {
            return url
        }

        // Stage 3: Wikipedia GeoSearch cross-reference (≤ 50 m).
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return await wikipediaService.closestWikipediaURL(near: location, languageCode: languageCode)
    }

    // MARK: - Stage 1: wikipedia tag

    /// Parses a `{lang}:{Article_Title}` OSM tag value into a Wikipedia URL.
    /// Returns nil if the tag is absent, malformed, or produces an invalid URL.
    func resolveFromWikipediaTag(_ tag: String?) -> URL? {
        guard let tag, let colonIdx = tag.firstIndex(of: ":") else { return nil }
        let lang  = String(tag[tag.startIndex..<colonIdx])
        let title = String(tag[tag.index(after: colonIdx)...])
        guard !lang.isEmpty, !title.isEmpty else { return nil }
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return URL(string: "https://\(lang).wikipedia.org/wiki/\(encoded)")
    }

    // MARK: - Stage 2: wikidata tag

    /// Queries the Wikidata sitelinks API for the given entity ID.
    /// Prefers the user's selected language; falls back to English in the same request.
    private func resolveFromWikidata(id: String, languageCode: String) async -> URL? {
        let prefSite   = "\(languageCode)wiki"
        let siteFilter = prefSite == "enwiki" ? "enwiki" : "\(prefSite)|enwiki"

        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action",     value: "wbgetentities"),
            URLQueryItem(name: "ids",        value: id),
            URLQueryItem(name: "props",      value: "sitelinks"),
            URLQueryItem(name: "sitefilter", value: siteFilter),
            URLQueryItem(name: "format",     value: "json"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response  = try JSONDecoder().decode(WikidataResponse.self, from: data)
            guard let entity = response.entities[id] else { return nil }

            // Prefer the user's language; fall back to English.
            let (sitelink, lang): (WikidataSitelink, String)
            if let pref = entity.sitelinks[prefSite] {
                (sitelink, lang) = (pref, languageCode)
            } else if let en = entity.sitelinks["enwiki"] {
                (sitelink, lang) = (en, "en")
            } else {
                return nil
            }

            let encoded = sitelink.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sitelink.title
            return URL(string: "https://\(lang).wikipedia.org/wiki/\(encoded)")
        } catch {
            return nil
        }
    }
}

// MARK: - Wikidata API Response Models

private struct WikidataResponse: Codable {
    let entities: [String: WikidataEntity]
}

private struct WikidataEntity: Codable {
    let sitelinks: [String: WikidataSitelink]
}

private struct WikidataSitelink: Codable {
    let title: String
}
