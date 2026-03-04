import SwiftUI

// MARK: - SettingsView (LAR-2)
// Lets users configure data sources (LAR-3), distance filter (LAR-4),
// and category filters (LAR-5).

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Data Sources (LAR-3, LAR-11)
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

                // MARK: Distance Filter (LAR-4)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Distance")
                            Spacer()
                            Text("\(Int(settings.maxDistanceKm)) km")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.maxDistanceKm,
                            in: 1...50,
                            step: 1
                        ) {
                            Text("Max Distance")
                        } minimumValueLabel: {
                            Text("1 km").font(.caption)
                        } maximumValueLabel: {
                            Text("50 km").font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Distance")
                } footer: {
                    Text("Only show landmarks within this radius of your location.")
                }

                // MARK: Category Filters (LAR-5)
                Section {
                    Toggle(isOn: $settings.showHistorical) {
                        Label("Historical", systemImage: "building.columns.fill")
                    }
                    Toggle(isOn: $settings.showNatural) {
                        Label("Natural", systemImage: "mountain.2.fill")
                    }
                    Toggle(isOn: $settings.showCultural) {
                        Label("Cultural", systemImage: "theatermasks.fill")
                    }
                    Toggle(isOn: $settings.showOther) {
                        Label("Other", systemImage: "mappin.circle.fill")
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Filter which types of landmarks appear in AR.")
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
