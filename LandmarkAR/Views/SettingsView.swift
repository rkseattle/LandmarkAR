import SwiftUI

// MARK: - SettingsView (LAR-2)
// Lets users configure data sources (LAR-3), distance filter (LAR-4),
// and category filters (LAR-5).

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var errorLogger: ErrorLogger
    @Environment(\.dismiss) private var dismiss

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
                    Text("Data Sources")
                } footer: {
                    Text("Enable or disable location data from each source.")
                }

                // MARK: Display Limit (LAR-23)
                Section {
                    Picker("Max Landmarks", selection: $settings.maxLandmarkCount) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("25").tag(25)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Display Limit")
                } footer: {
                    Text("Maximum landmarks shown at once. The closest and farthest are always included.")
                }

                // MARK: Label Size (LAR-29)
                Section {
                    Picker("Label Size", selection: $settings.labelDisplaySize) {
                        Text("Small").tag(LabelDisplaySize.small)
                        Text("Medium").tag(LabelDisplaySize.medium)
                        Text("Large").tag(LabelDisplaySize.large)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Label Size")
                } footer: {
                    Text("Controls the size of icons and text on the AR view.")
                }

                // MARK: Category Filters + Distance (LAR-5, LAR-13, LAR-24)
                // Toggle and distance slider are grouped per category.
                // The slider is only shown when the category is enabled.
                Section {
                    CategoryRow(label: "Historical", systemImage: "building.columns.fill",
                                isEnabled: $settings.showHistorical,
                                distanceIndex: $settings.maxDistanceIndexHistorical)
                    CategoryRow(label: "Natural", systemImage: "mountain.2.fill",
                                isEnabled: $settings.showNatural,
                                distanceIndex: $settings.maxDistanceIndexNatural)
                    CategoryRow(label: "Cultural", systemImage: "theatermasks.fill",
                                isEnabled: $settings.showCultural,
                                distanceIndex: $settings.maxDistanceIndexCultural)
                    CategoryRow(label: "Other", systemImage: "mappin.circle.fill",
                                isEnabled: $settings.showOther,
                                distanceIndex: $settings.maxDistanceIndexOther)
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Enable categories and set the maximum distance for each.")
                }

                // MARK: Real-time Updates (LAR-25, LAR-28)
                Section {
                    Picker("Real-time Updates", selection: $settings.realtimeUpdateMode) {
                        Text("Off").tag(RealtimeUpdateMode.off)
                        Text("Wi-Fi Only").tag(RealtimeUpdateMode.wifiOnly)
                        Text("Always").tag(RealtimeUpdateMode.always)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Real-time Updates")
                } footer: {
                    Text("Refreshes landmarks every 30 s or after moving 50 m. \"Wi-Fi Only\" skips updates on cellular to save data.")
                }

                // MARK: Error Log (LAR-16)
                Section {
                    NavigationLink {
                        ErrorLogView(logger: errorLogger)
                    } label: {
                        Label("Error Log", systemImage: "exclamationmark.triangle")
                    }
                } header: {
                    Text("Diagnostics")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - CategoryRow (LAR-13, LAR-24)
// A form row combining a category toggle with a conditional distance slider.
// The slider is hidden when the category is disabled, but its value is preserved.

private struct CategoryRow: View {
    let label: String
    let systemImage: String
    @Binding var isEnabled: Bool
    @Binding var distanceIndex: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Label(label, systemImage: systemImage)
            }
            if isEnabled {
                HStack {
                    Spacer()
                    Text(AppSettings.distanceLabel(forIndex: distanceIndex))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $distanceIndex, in: 0...6, step: 1) {
                    Text(label)
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
