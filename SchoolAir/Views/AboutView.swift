import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Your readings") {
                    explanation("Indoor CO₂", "Carbon dioxide in parts per million (ppm), measured by the indoor box. Helps you follow room ventilation.", "person.3")
                    explanation("Portable PM2.5", "Fine particles in µg/m³, measured where the portable box sits. No experimental humidity correction is applied.", "aqi.medium")
                    explanation("Outside AQI", "A regional US air-quality index. Estimate means it comes from an air-quality model, not a nearby monitoring station.", "globe.americas")
                }
                Section("Weather & outdoor air") {
                    Text("The Weather tab shows Evansville conditions, hourly and seven-day forecasts, wind, humidity, precipitation chance, daily UV peak, sunrise and sunset. Temperature units can be changed there without changing sensor units.")
                    Text("The default report uses the CAMS model via Open-Meteo for Evansville. It covers roughly 45 km. Particle AQI uses a 24-hour modeled average, so it will differ from your portable sensor’s current reading.")
                    Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                    Link("CAMS", destination: URL(string: "https://atmosphere.copernicus.eu/")!)
                }
                Section("Portable location") {
                    Text("Stand next to the portable box and tap ‘The box is next to me.’ The app saves that spot on this phone until you update or clear it. Walking away does not move the saved location. The sensor has no GPS, and coordinates are not uploaded to Firebase.")
                }
                Section("Freshness & history") {
                    Text("Live means a reading arrived within the last three minutes. Stale readings remain visible with their original timestamp.")
                    Text("History shows five-minute averages for 24 hours and thirty-minute averages for 7 days. Gaps remain visible; statistics use the original samples. Event markers are notes you add yourself.")
                }
                Section {
                    DisclosureGroup("About the colors") {
                        Text("CO₂ colors are ventilation prompts. PM2.5 colors use concentration bands; they are not an official AQI or a safety guarantee.")
                        ForEach(CO2Bands.all, id: \.self) { band in
                            LabeledContent(band.label, value: "\(band.range) ppm")
                        }
                    }
                }
            }
            .font(.subheadline)
            .navigationTitle("About School Air").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func explanation(_ title: String, _ text: String, _ icon: String) -> some View {
        Label { VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }.padding(.vertical, 4) } icon: { Image(systemName: icon).foregroundStyle(.tint) }
    }
}
