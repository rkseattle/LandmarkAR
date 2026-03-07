import SwiftUI

// MARK: - Locale Bundle Environment Key (LAR-35)
// Injects the language-specific Bundle into the SwiftUI environment so all
// views can look up localized strings without requiring a restart.

struct LocaleBundleKey: EnvironmentKey {
    static let defaultValue: Bundle = .main
}

extension EnvironmentValues {
    var localeBundle: Bundle {
        get { self[LocaleBundleKey.self] }
        set { self[LocaleBundleKey.self] = newValue }
    }
}
