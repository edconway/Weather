import SwiftUI
import UIKit
import WeatherCore

/// Units, theme override, and the attribution required by §13.
struct SettingsSheet: View {
    @Bindable var store: WeatherStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $store.imperial) {
                        Text("°C · km/h · mm").tag(false)
                        Text("°F · mph · in").tag(true)
                    }
                    .pickerStyle(.segmented)
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

                Section("Data sources") {
                    sourceRow(AppleWeatherStatus.openMeteoLine(
                        isStale: store.forecastIsStale,
                        updatedAt: store.forecastUpdatedAt,
                        now: Date(),
                        timeZone: store.locationTimeZone))
                    sourceRow(AppleWeatherStatus.appleLine(store.appleWeather))
                    if let attribution = store.appleWeather?.attribution {
                        AppleAttributionView(attribution: attribution)
                    }
                    #if DEBUG
                    Button("Copy diagnostics") {
                        UIPasteboard.general.string = Self.diagnostics(for: store)
                    }
                    #endif
                }

                Section("About") {
                    LabeledContent("App", value: "Weather World")
                    Link(destination: URL(string: "https://open-meteo.com")!) {
                        LabeledContent("Weather data", value: "Open-Meteo")
                    }
                    Text("Forecast & historical data from Open-Meteo, licensed CC BY 4.0. "
                         + "Location names are resolved on-device. "
                         + "Minute-by-minute rain on this iPhone comes from Apple Weather.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Your coordinates are sent to Open-Meteo for the forecast and history, "
                         + "and to Apple Weather on this iPhone for minute-by-minute rain. "
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

    private func sourceRow(_ line: SourceStatusLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.badgeColor(line.badge))
                .frame(width: 64, alignment: .leading)
            Text(line.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private static func badgeColor(_ badge: String) -> Color {
        switch badge {
        case "Live": return Color(red: 0.18, green: 0.55, blue: 0.34)
        case "Limited": return Color(red: 0.72, green: 0.46, blue: 0.12)
        case "Retry": return Color(red: 0.70, green: 0.22, blue: 0.18)
        default: return .secondary
        }
    }

    /// Bundle, team, and the typed failure. The raw WeatherKit error stays in the log.
    private static func diagnostics(for store: WeatherStore) -> String {
        let failure = store.appleWeather?.failure?.rawValue ?? "none"
        let availability = store.appleWeather?.minuteAvailability.rawValue ?? "none"
        let minutes = store.appleWeather?.displayMinutes.count ?? 0
        return """
        bundle \(Bundle.main.bundleIdentifier ?? AppConfig.iOSBundleID)
        team \(AppConfig.developmentTeamID)
        failure \(failure)
        availability \(availability)
        minutes \(minutes)
        """
    }
}
