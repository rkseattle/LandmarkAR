import Foundation

// MARK: - AppSettings
// Persists user preferences via UserDefaults.
// Shared across the app via @StateObject / @EnvironmentObject.

class AppSettings: ObservableObject {

    // MARK: - Data Sources (LAR-3, LAR-11, LAR-12)
    @Published var isWikipediaEnabled: Bool {
        didSet { UserDefaults.standard.set(isWikipediaEnabled, forKey: Keys.isWikipediaEnabled) }
    }
    @Published var isOpenStreetMapEnabled: Bool {
        didSet { UserDefaults.standard.set(isOpenStreetMapEnabled, forKey: Keys.isOpenStreetMapEnabled) }
    }
    @Published var isNPSEnabled: Bool {
        didSet { UserDefaults.standard.set(isNPSEnabled, forKey: Keys.isNPSEnabled) }
    }
    @Published var npsApiKey: String {
        didSet { UserDefaults.standard.set(npsApiKey, forKey: Keys.npsApiKey) }
    }

    // MARK: - Distance Filter (LAR-4)
    /// Maximum distance in km — landmarks beyond this are excluded
    @Published var maxDistanceKm: Double {
        didSet { UserDefaults.standard.set(maxDistanceKm, forKey: Keys.maxDistanceKm) }
    }

    // MARK: - Category Filters (LAR-5)
    @Published var showHistorical: Bool {
        didSet { UserDefaults.standard.set(showHistorical, forKey: Keys.showHistorical) }
    }
    @Published var showNatural: Bool {
        didSet { UserDefaults.standard.set(showNatural, forKey: Keys.showNatural) }
    }
    @Published var showCultural: Bool {
        didSet { UserDefaults.standard.set(showCultural, forKey: Keys.showCultural) }
    }
    @Published var showOther: Bool {
        didSet { UserDefaults.standard.set(showOther, forKey: Keys.showOther) }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        isWikipediaEnabled     = ud.object(forKey: Keys.isWikipediaEnabled)     as? Bool ?? true
        isOpenStreetMapEnabled = ud.object(forKey: Keys.isOpenStreetMapEnabled) as? Bool ?? true
        isNPSEnabled           = ud.object(forKey: Keys.isNPSEnabled)           as? Bool ?? false
        npsApiKey              = ud.string(forKey: Keys.npsApiKey) ?? "H7f7Y1eEtjYH7it8HOI2YOp6aBicGNA5FWeyDhPN"
        maxDistanceKm          = ud.object(forKey: Keys.maxDistanceKm)          as? Double ?? 10.0
        showHistorical         = ud.object(forKey: Keys.showHistorical)         as? Bool ?? true
        showNatural            = ud.object(forKey: Keys.showNatural)            as? Bool ?? true
        showCultural           = ud.object(forKey: Keys.showCultural)           as? Bool ?? true
        showOther              = ud.object(forKey: Keys.showOther)              as? Bool ?? true
    }

    // MARK: - Private

    private enum Keys {
        static let isWikipediaEnabled     = "isWikipediaEnabled"
        static let isOpenStreetMapEnabled = "isOpenStreetMapEnabled"
        static let isNPSEnabled           = "isNPSEnabled"
        static let npsApiKey              = "npsApiKey"
        static let maxDistanceKm          = "maxDistanceKm"
        static let showHistorical         = "showHistorical"
        static let showNatural            = "showNatural"
        static let showCultural           = "showCultural"
        static let showOther              = "showOther"
    }
}
