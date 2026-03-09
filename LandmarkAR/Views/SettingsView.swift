import SwiftUI

// MARK: - SettingsView (LAR-2)
// Lets users configure data sources (LAR-3), distance filter (LAR-4),
// category filters (LAR-5), and language (LAR-35).

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var errorLogger: ErrorLogger
    @Environment(\.dismiss) private var dismiss

    // LAR-35: Use the language-specific bundle from settings for immediate updates.
    private var bundle: Bundle { settings.localizedBundle }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Data Sources (LAR-3, LAR-11, LAR-12)
                Section {
                    Toggle(isOn: $settings.isWikipediaEnabled) {
                        Label("Wikipedia", systemImage: "globe")
                    }
                    Toggle(isOn: $settings.isOpenStreetMapEnabled) {
                        Label("OpenStreetMap", systemImage: "map")
                    }
                } header: {
                    Text("settings.dataSources.header", bundle: bundle)
                } footer: {
                    Text("settings.dataSources.footer", bundle: bundle)
                }

                // MARK: Filters (LAR-5, LAR-13, LAR-23, LAR-24, LAR-39)
                // Category toggles + per-category distance, significance filter, and display limit
                // are all grouped here because they collectively answer "what landmarks appear".
                Section {
                    CategoryRow(label: Text("settings.categories.historical", bundle: bundle),
                                systemImage: "building.columns.fill",
                                isEnabled: $settings.showHistorical,
                                distanceIndex: $settings.maxDistanceIndexHistorical,
                                distanceUnit: settings.distanceUnit)
                    CategoryRow(label: Text("settings.categories.natural", bundle: bundle),
                                systemImage: "mountain.2.fill",
                                isEnabled: $settings.showNatural,
                                distanceIndex: $settings.maxDistanceIndexNatural,
                                distanceUnit: settings.distanceUnit)
                    CategoryRow(label: Text("settings.categories.cultural", bundle: bundle),
                                systemImage: "theatermasks.fill",
                                isEnabled: $settings.showCultural,
                                distanceIndex: $settings.maxDistanceIndexCultural,
                                distanceUnit: settings.distanceUnit)
                    CategoryRow(label: Text("settings.categories.other", bundle: bundle),
                                systemImage: "mappin.circle.fill",
                                isEnabled: $settings.showOther,
                                distanceIndex: $settings.maxDistanceIndexOther,
                                distanceUnit: settings.distanceUnit)
                    Toggle(isOn: $settings.isIconicLandmarksOnly) {
                        Label {
                            Text("settings.significance.iconicLandmarksOnly", bundle: bundle)
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                    }
                    Picker(selection: $settings.maxLandmarkCount) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("25").tag(25)
                    } label: {
                        Text("settings.displayLimit.maxLandmarks", bundle: bundle)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("settings.filters.header", bundle: bundle)
                } footer: {
                    Text("settings.filters.footer", bundle: bundle)
                }

                // MARK: Appearance (LAR-29)
                // Distance units and label size both control how things look in AR.
                Section {
                    Picker(selection: $settings.distanceUnit) {
                        Text("settings.distanceUnit.km",    bundle: bundle).tag(DistanceUnit.kilometers)
                        Text("settings.distanceUnit.miles", bundle: bundle).tag(DistanceUnit.miles)
                    } label: {
                        Text("settings.distanceUnit.header", bundle: bundle)
                    }
                    .pickerStyle(.segmented)
                    Picker(selection: $settings.labelDisplaySize) {
                        Text("settings.labelSize.small",  bundle: bundle).tag(LabelDisplaySize.small)
                        Text("settings.labelSize.medium", bundle: bundle).tag(LabelDisplaySize.medium)
                        Text("settings.labelSize.large",  bundle: bundle).tag(LabelDisplaySize.large)
                    } label: {
                        Text("settings.labelSize.header", bundle: bundle)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("settings.appearance.header", bundle: bundle)
                } footer: {
                    Text("settings.labelSize.footer", bundle: bundle)
                }

                // MARK: Real-time Updates (LAR-25, LAR-28)
                Section {
                    Picker(selection: $settings.realtimeUpdateMode) {
                        Text("settings.realtimeUpdates.off",      bundle: bundle).tag(RealtimeUpdateMode.off)
                        Text("settings.realtimeUpdates.wifiOnly", bundle: bundle).tag(RealtimeUpdateMode.wifiOnly)
                        Text("settings.realtimeUpdates.always",   bundle: bundle).tag(RealtimeUpdateMode.always)
                    } label: {
                        Text("settings.realtimeUpdates.header", bundle: bundle)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("settings.realtimeUpdates.header", bundle: bundle)
                } footer: {
                    Text("settings.realtimeUpdates.footer", bundle: bundle)
                }

                // MARK: App (LAR-16, LAR-35)
                // Language and diagnostics share this section as app-level settings.
                Section {
                    Picker(selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    } label: {
                        Label {
                            Text("settings.language.label", bundle: bundle)
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                    .pickerStyle(.navigationLink)
                    NavigationLink {
                        ErrorLogView(logger: errorLogger)
                            .environment(\.localeBundle, bundle)
                    } label: {
                        Label {
                            Text("settings.errorLog", bundle: bundle)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                } header: {
                    Text("settings.app.header", bundle: bundle)
                } footer: {
                    Text("settings.language.footer", bundle: bundle)
                }
            }
            .navigationTitle(Text("settings.title", bundle: bundle))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("settings.done", bundle: bundle)
                    }
                }
            }
        }
    }
}

// MARK: - CategoryRow (LAR-13, LAR-24)
// A form row combining a category toggle with a conditional distance slider.
// The slider is hidden when the category is disabled, but its value is preserved.

private struct CategoryRow: View {
    let label: Text
    let systemImage: String
    @Binding var isEnabled: Bool
    @Binding var distanceIndex: Double
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Label(title: { label }, icon: { Image(systemName: systemImage) })
            }
            if isEnabled {
                HStack {
                    Spacer()
                    Text(distanceUnit.sliderLabel(km: AppSettings.km(forIndex: distanceIndex)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $distanceIndex, in: 0...6, step: 1) {
                    label
                } minimumValueLabel: {
                    Text("0.1").font(.caption2)
                } maximumValueLabel: {
                    Text("100").font(.caption2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
