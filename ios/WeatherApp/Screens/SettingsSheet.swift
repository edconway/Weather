import SwiftUI
import WeatherCore

/// Units, theme override, and the attribution required by §13.
struct SettingsSheet: View {
    @Bindable var store: WeatherStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Temperature", selection: $store.imperial) {
                        Text("Celsius, km/h, mm").tag(false)
                        Text("Fahrenheit, mph, inches").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Appearance") {
                    Picker("Theme", selection: $store.theme) {
                        ForEach(Prefs.ThemeOverride.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("About") {
                    LabeledContent("App", value: "Weather World")
                    Link(destination: URL(string: "https://open-meteo.com")!) {
                        LabeledContent("Weather data", value: "Open-Meteo")
                    }
                    Text("Forecast & historical data from Open-Meteo, licensed CC BY 4.0. "
                         + "Location names are resolved on-device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Your coordinates are sent to Open-Meteo to fetch weather. "
                         + "Nothing else leaves this device, and nothing is tracked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
