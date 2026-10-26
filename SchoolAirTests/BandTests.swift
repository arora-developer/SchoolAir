import Testing
@testable import SchoolAir

struct BandTests {
    @Test("PM2.5 bands follow the EPA 2024 breakpoints on one decimal")
    func pm25Breakpoints() {
        let cases: [(Double, String)] = [
            (0, "Good"), (9.0, "Good"), (9.04, "Good"),
            (9.1, "Moderate"), (35.4, "Moderate"),
            (35.5, "Unhealthy for sensitive groups"), (55.4, "Unhealthy for sensitive groups"),
            (55.5, "Unhealthy"), (125.4, "Unhealthy"),
            (125.5, "Very unhealthy"), (225.4, "Very unhealthy"),
            (225.5, "Hazardous"), (900, "Hazardous"),
        ]
        for (value, label) in cases {
            #expect(PM25Bands.band(for: value).label == label, "\(value) µg/m³")
        }
    }

    @Test("Negative particle values are clamped to Good rather than crashing or going weird")
    func negativeClamp() {
        #expect(PM25Bands.band(for: -3).tone == .green)
    }

    @Test("CO2 bands are the ventilation prompts from the plan")
    func co2Bands() {
        #expect(CO2Bands.band(for: 450).tone == .green)
        #expect(CO2Bands.band(for: 799).tone == .green)
        #expect(CO2Bands.band(for: 800).tone == .yellow)
        #expect(CO2Bands.band(for: 999).tone == .yellow)
        #expect(CO2Bands.band(for: 1000).tone == .orange)
        #expect(CO2Bands.band(for: 1500).tone == .orange)
        #expect(CO2Bands.band(for: 1501).tone == .red)
    }

    @Test("AirNow category numbers map to the six AQI colors")
    func aqiTones() {
        #expect(AQIBands.tone(forCategory: 1) == .green)
        #expect(AQIBands.tone(forCategory: 2) == .yellow)
        #expect(AQIBands.tone(forCategory: 3) == .orange)
        #expect(AQIBands.tone(forCategory: 4) == .red)
        #expect(AQIBands.tone(forCategory: 5) == .purple)
        #expect(AQIBands.tone(forCategory: 6) == .maroon)
        #expect(AQIBands.tone(forCategory: 9) == .gray)
    }

    @Test("The humidity correction matches the published coefficients")
    func humidityCorrection() {
        // 0.524 × 20 − 0.0862 × 50 + 5.75 = 11.92
        #expect(abs(HumidityCorrection.adjustedPM25(cf1: 20, rh: 50) - 11.92) < 0.001)
        #expect(HumidityCorrection.adjustedPM25(cf1: 0, rh: 100) == 0, "never negative")
    }
}
