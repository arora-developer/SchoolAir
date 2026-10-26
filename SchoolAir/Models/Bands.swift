import Foundation

/// The colour a number is painted with. Views map tones to real colours; models stay UI-free.
enum Tone: String, Hashable, Sendable, CaseIterable {
    case green, yellow, orange, red, purple, maroon, gray
}

/// A labelled range for one measurement.
struct Band: Hashable, Sendable {
    let tone: Tone
    let label: String
    let range: String
}

/// PM2.5 concentration bands, in µg/m³.
///
/// Indicative only. These are the EPA's 2024 index breakpoints applied to a one-minute average.
/// An official AQI is computed on 24-hour or multi-hour averages, so this is never called an AQI.
enum PM25Bands {
    static let all: [Band] = [
        Band(tone: .green, label: "Good", range: "0 to 9.0"),
        Band(tone: .yellow, label: "Moderate", range: "9.1 to 35.4"),
        Band(tone: .orange, label: "Unhealthy for sensitive groups", range: "35.5 to 55.4"),
        Band(tone: .red, label: "Unhealthy", range: "55.5 to 125.4"),
        Band(tone: .purple, label: "Very unhealthy", range: "125.5 to 225.4"),
        Band(tone: .maroon, label: "Hazardous", range: "225.5 and up"),
    ]

    static func band(for micrograms: Double) -> Band {
        // EPA works on one decimal. Round first so 9.04 is Good and 9.05 is Moderate.
        let v = max(0, (micrograms * 10).rounded() / 10)
        switch v {
        case ...9.0: return all[0]
        case ...35.4: return all[1]
        case ...55.4: return all[2]
        case ...125.4: return all[3]
        case ...225.4: return all[4]
        default: return all[5]
        }
    }
}

/// CO2 bands, in parts per million.
///
/// Configurable ventilation prompts, not health categories.
enum CO2Bands {
    static let all: [Band] = [
        Band(tone: .green, label: "Good", range: "under 800"),
        Band(tone: .yellow, label: "Fair", range: "800 to 1,000"),
        Band(tone: .orange, label: "Poor", range: "1,000 to 1,500"),
        Band(tone: .red, label: "Bad", range: "over 1,500"),
    ]

    static func band(for ppm: Double) -> Band {
        switch ppm {
        case ..<800: return all[0]
        case ..<1000: return all[1]
        case ...1500: return all[2]
        default: return all[3]
        }
    }
}

/// AirNow's six AQI categories, by category number.
enum AQIBands {
    static func tone(forCategory number: Int) -> Tone {
        switch number {
        case 1: .green
        case 2: .yellow
        case 3: .orange
        case 4: .red
        case 5: .purple
        case 6: .maroon
        default: .gray
        }
    }
}
