import CoreLocation
import Foundation

// MARK: - LabelDisplaySize (LAR-29)

enum LabelDisplaySize: String, CaseIterable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"
}

// MARK: - LabelDisplaySize Distance Scaling (LAR-43)

extension LabelDisplaySize {

    // Distance thresholds for logarithmic label size interpolation.
    static let minScaleDistanceMeters: CLLocationDistance = 200   // full (max) size at or below this
    static let maxScaleDistanceMeters: CLLocationDistance = 5000  // minimum size at or above this

    // Minimum readable sizes applied as a floor regardless of distance or user setting.
    static let minTitleFontSize: CGFloat    = 10
    static let minDistanceFontSize: CGFloat = 8

    // Maximum title font size — applied when a landmark is within minScaleDistanceMeters.
    var maxTitleFontSize: CGFloat {
        switch self {
        case .small:  return 13
        case .medium: return 17
        case .large:  return 22
        }
    }

    // Distance badge font is always 65% of the title font size.
    var maxDistanceFontSize: CGFloat { (maxTitleFontSize * 0.65).rounded() }

    // Maximum label width — applied when a landmark is within minScaleDistanceMeters.
    var maxLabelWidth: CGFloat {
        switch self {
        case .small:  return 130
        case .medium: return 165
        case .large:  return 210
        }
    }

    // Category icon size (unchanged from LAR-29 values).
    var iconSize: CGFloat {
        switch self {
        case .small:  return 16
        case .medium: return 22
        case .large:  return 30
        }
    }

    /// Returns a scale factor in [0, 1] using an inverse logarithmic curve.
    /// 1.0 at ≤minScaleDistanceMeters (full size), 0.0 at ≥maxScaleDistanceMeters (minimum size).
    static func scaleFactor(for distanceMeters: CLLocationDistance) -> CGFloat {
        let clamped = max(minScaleDistanceMeters, min(maxScaleDistanceMeters, distanceMeters))
        let logRange = log(maxScaleDistanceMeters) - log(minScaleDistanceMeters)
        return CGFloat((log(maxScaleDistanceMeters) - log(clamped)) / logRange)
    }
}

// MARK: - RealtimeUpdateMode (LAR-28)

enum RealtimeUpdateMode: String, CaseIterable {
    case off      = "off"
    case wifiOnly = "wifiOnly"
    case always   = "always"
}

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

    // LAR-39: When enabled, only landmarks with 10,000+ monthly Wikipedia views are shown.
    @Published var isIconicLandmarksOnly: Bool {
        didSet { UserDefaults.standard.set(isIconicLandmarksOnly, forKey: Keys.isIconicLandmarksOnly) }
    }

    // MARK: - Distance Filter (LAR-4, LAR-13)
    // Each category has its own distance slider indexed into distanceSteps.
    // The overall maxDistanceKm is the max of all four, used as the API fetch radius.

    /// Discrete km values available on each category distance slider.
    static let distanceSteps: [Double] = [0.1, 0.5, 1, 5, 10, 25, 100]

    /// Maps a slider index (0...6) to a km value.
    static func km(forIndex index: Double) -> Double {
        let i = max(0, min(Int(index.rounded()), distanceSteps.count - 1))
        return distanceSteps[i]
    }

    /// Formatted display string for a slider index.
    static func distanceLabel(forIndex index: Double) -> String {
        let km = Self.km(forIndex: index)
        return km < 1 ? "\(km) km" : "\(Int(km)) km"
    }

    @Published var maxDistanceIndexHistorical: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexHistorical, value: maxDistanceIndexHistorical) }
    }
    @Published var maxDistanceIndexNatural: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexNatural, value: maxDistanceIndexNatural) }
    }
    @Published var maxDistanceIndexCultural: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexCultural, value: maxDistanceIndexCultural) }
    }
    @Published var maxDistanceIndexOther: Double {
        didSet { deferredWrite(key: Keys.maxDistanceIndexOther, value: maxDistanceIndexOther) }
    }

    var maxDistanceKmHistorical: Double { AppSettings.km(forIndex: maxDistanceIndexHistorical) }
    var maxDistanceKmNatural:    Double { AppSettings.km(forIndex: maxDistanceIndexNatural) }
    var maxDistanceKmCultural:   Double { AppSettings.km(forIndex: maxDistanceIndexCultural) }
    var maxDistanceKmOther:      Double { AppSettings.km(forIndex: maxDistanceIndexOther) }

    /// Overall fetch radius — the maximum distance among enabled categories only (LAR-24).
    var maxDistanceKm: Double {
        var distances: [Double] = []
        if showHistorical { distances.append(maxDistanceKmHistorical) }
        if showNatural    { distances.append(maxDistanceKmNatural) }
        if showCultural   { distances.append(maxDistanceKmCultural) }
        if showOther      { distances.append(maxDistanceKmOther) }
        return distances.max() ?? 0
    }

    // MARK: - Display Limit (LAR-23)
    /// Maximum number of landmarks shown at once. Options: 5, 10, 25.
    @Published var maxLandmarkCount: Int {
        didSet { UserDefaults.standard.set(maxLandmarkCount, forKey: Keys.maxLandmarkCount) }
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

    // MARK: - Label Display Size (LAR-29)
    @Published var labelDisplaySize: LabelDisplaySize {
        didSet { UserDefaults.standard.set(labelDisplaySize.rawValue, forKey: Keys.labelDisplaySize) }
    }

    // MARK: - Language (LAR-35)
    // Stored as the BCP 47 locale code. Defaults to the device system language if supported,
    // otherwise falls back to English.
    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    /// The Bundle for the current language's .lproj directory.
    /// Views pass this to Text(_, bundle:) so language changes take effect immediately.
    var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: appLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    // MARK: - Real-time Updates (LAR-25, LAR-28)
    /// Controls automatic landmark refresh: off, wi-fi only, or always.
    @Published var realtimeUpdateMode: RealtimeUpdateMode {
        didSet { UserDefaults.standard.set(realtimeUpdateMode.rawValue, forKey: Keys.realtimeUpdateMode) }
    }

    // MARK: - Deferred Persistence

    // Debounces UserDefaults writes for the four continuous distance sliders so rapid
    // drag events don't cause dozens of synchronous disk writes on the main thread.
    // All other settings (toggles, pickers) write immediately via UserDefaults.standard.set()
    // in their didSet so reads from a new AppSettings() instance are always consistent.
    private var pendingWrites: [String: DispatchWorkItem] = [:]

    private func deferredWrite(key: String, value: Any) {
        pendingWrites[key]?.cancel()
        let item = DispatchWorkItem { UserDefaults.standard.set(value, forKey: key) }
        pendingWrites[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        isWikipediaEnabled     = ud.object(forKey: Keys.isWikipediaEnabled)     as? Bool ?? true
        isOpenStreetMapEnabled = ud.object(forKey: Keys.isOpenStreetMapEnabled) as? Bool ?? true
        isIconicLandmarksOnly  = ud.object(forKey: Keys.isIconicLandmarksOnly)  as? Bool ?? false
        let savedMode = ud.string(forKey: Keys.realtimeUpdateMode).flatMap(RealtimeUpdateMode.init(rawValue:))
        realtimeUpdateMode = savedMode ?? .off
        let savedSize = ud.string(forKey: Keys.labelDisplaySize).flatMap(LabelDisplaySize.init(rawValue:))
        labelDisplaySize = savedSize ?? .medium
        let savedLang = ud.string(forKey: Keys.appLanguage).flatMap(AppLanguage.init(rawValue:))
        appLanguage = savedLang ?? AppLanguage.systemDefault()
        // Default index 4 = 10 km (matches old default)
        maxDistanceIndexHistorical = ud.object(forKey: Keys.maxDistanceIndexHistorical) as? Double ?? 4
        maxDistanceIndexNatural    = ud.object(forKey: Keys.maxDistanceIndexNatural)    as? Double ?? 4
        maxDistanceIndexCultural   = ud.object(forKey: Keys.maxDistanceIndexCultural)   as? Double ?? 4
        maxDistanceIndexOther      = ud.object(forKey: Keys.maxDistanceIndexOther)      as? Double ?? 4
        maxLandmarkCount       = ud.object(forKey: Keys.maxLandmarkCount)       as? Int    ?? 10
        showHistorical         = ud.object(forKey: Keys.showHistorical)         as? Bool ?? true
        showNatural            = ud.object(forKey: Keys.showNatural)            as? Bool ?? true
        showCultural           = ud.object(forKey: Keys.showCultural)           as? Bool ?? true
        showOther              = ud.object(forKey: Keys.showOther)              as? Bool ?? true
    }

    // MARK: - Private

    private enum Keys {
        static let isWikipediaEnabled          = "isWikipediaEnabled"
        static let isOpenStreetMapEnabled      = "isOpenStreetMapEnabled"
        static let realtimeUpdateMode          = "realtimeUpdateMode"
        static let labelDisplaySize            = "labelDisplaySize"
        static let maxDistanceIndexHistorical  = "maxDistanceIndexHistorical"
        static let maxDistanceIndexNatural     = "maxDistanceIndexNatural"
        static let maxDistanceIndexCultural    = "maxDistanceIndexCultural"
        static let maxDistanceIndexOther       = "maxDistanceIndexOther"
        static let maxLandmarkCount            = "maxLandmarkCount"
        static let showHistorical              = "showHistorical"
        static let showNatural                 = "showNatural"
        static let showCultural                = "showCultural"
        static let showOther                   = "showOther"
        static let appLanguage                 = "appLanguage"
        static let isIconicLandmarksOnly       = "isIconicLandmarksOnly"
    }
}
