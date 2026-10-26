import Testing
import Foundation
@testable import SchoolAir

struct RegionalModelTests {
    private let now = Date(timeIntervalSince1970: 1_792_281_600)
    private let response = #"{"current_units":{"time":"unixtime","us_aqi":"USAQI","pm2_5":"μg/m³"},"current":{"time":1792281600,"us_aqi":34,"pm2_5":5.4}}"#

    @Test("Live response shape preserves units, source, time and modeled status")
    func valid() throws {
        let report = try OpenMeteoClient.decode(Data(response.utf8), now: now)
        #expect(report.aqi == 34)
        #expect(report.pm25 == 5.4)
        #expect(report.categoryName == "Good")
        #expect(report.observed == now)
        #expect(report.isModeled && !report.isPlaceholder)
        #expect(report.sourceLabel.contains("CAMS"))
    }

    @Test("Missing AQI, wrong units and old timestamps never become a live number")
    func invalid() {
        for invalid in [response.replacingOccurrences(of: "USAQI", with: "μg/m³"),
                        response.replacingOccurrences(of: "\"us_aqi\":34", with: "\"us_aqi\":null"),
                        response.replacingOccurrences(of: "1792281600", with: "1792000000")] {
            #expect(throws: (any Error).self) { try OpenMeteoClient.decode(Data(invalid.utf8), now: now) }
        }
    }

    @Test("Chart workload is bounded for seven days of ten-second records")
    func denseHistory() {
        let start = now.addingTimeInterval(-7 * 86_400)
        let samples: [(Date, Double?)] = (0..<60_480).map { (start.addingTimeInterval(Double($0 * 10)), Double($0 % 100)) }
        let week = HistorySeries.build(samples: samples, from: start, to: now, bucket: 1800)
        #expect(week.points.count <= 336)
        #expect(week.gaps.isEmpty)
    }
}
