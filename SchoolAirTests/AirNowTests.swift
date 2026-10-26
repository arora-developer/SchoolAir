import Testing
import Foundation
@testable import SchoolAir

struct AirNowTests {
    /// The documented shape of AirNow's current-observation response. Unverified against a live call.
    private let sample = """
    [
      {"DateObserved":"2026-09-19 ","HourObserved":13,"LocalTimeZone":"EST","ReportingArea":"Evansville","StateCode":"IN",
       "Latitude":37.97,"Longitude":-87.57,"ParameterName":"O3","AQI":38,"Category":{"Number":1,"Name":"Good"}},
      {"DateObserved":"2026-09-19 ","HourObserved":13,"LocalTimeZone":"EST","ReportingArea":"Evansville","StateCode":"IN",
       "Latitude":37.97,"Longitude":-87.57,"ParameterName":"PM2.5","AQI":42,"Category":{"Number":1,"Name":"Good"}}
    ]
    """

    @Test("The documented response decodes")
    func decodes() throws {
        let observations = try JSONDecoder().decode([AirNowClient.Observation].self, from: Data(sample.utf8))
        #expect(observations.count == 2)
        #expect(observations[1].parameterName == "PM2.5")
        #expect(observations[1].category.name == "Good")
    }

    @Test("The highest valid pollutant determines regional AQI")
    func prefersPM25() throws {
        let observations = try JSONDecoder().decode([AirNowClient.Observation].self, from: Data(sample.utf8))
        let pick = AirNowClient.pick(from: observations)
        #expect(pick?.parameterName == "PM2.5")
        #expect(pick?.regionalAQI.aqi == 42)
        #expect(pick?.regionalAQI.tone == .green)
        #expect(pick?.regionalAQI.isPlaceholder == false)
    }

    @Test("Without PM2.5 the highest AQI wins")
    func highestWithoutPM25() throws {
        let onlyOzone = sample.replacingOccurrences(of: "\"PM2.5\"", with: "\"PM10\"")
        let observations = try JSONDecoder().decode([AirNowClient.Observation].self, from: Data(onlyOzone.utf8))
        #expect(AirNowClient.pick(from: observations)?.aqi == 42)
    }

    @Test("The observation time is built from date, hour and time zone")
    func observedTime() throws {
        let observations = try JSONDecoder().decode([AirNowClient.Observation].self, from: Data(sample.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "EST")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: observations[0].observedDate)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 19 && parts.hour == 13)
    }


    @Test("Without a key production uses modeled regional data, not a fabricated value")
    func modeledByDefault() {
        #expect(AirNowProvider.makeDefault(bundle: Bundle(for: EventStore.self)) is OpenMeteoClient)
    }

    @Test("Ozone wins when its AQI is higher")
    func highestPollutant() throws {
        let data = sample.replacingOccurrences(of: "\"AQI\":38", with: "\"AQI\":80")
        let rows = try JSONDecoder().decode([AirNowClient.Observation].self, from: Data(data.utf8))
        #expect(AirNowClient.pick(from: rows)?.parameterName == "O3")
    }
}
