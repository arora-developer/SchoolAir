import Testing
import Foundation
@testable import SchoolAir

struct InsightsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minute(_ m: Int) -> Date { start.addingTimeInterval(Double(m) * 60) }

    private func indoor(_ m: Int, co2: Double?, boot: String = "a") -> IndoorReading {
        IndoorReading(t: minute(m), schemaVersion: 1, seq: m, bootId: boot, qualityFlags: [], co2: co2, tempC: 22, rh: 45)
    }

    private func portable(_ m: Int, pm: Double?) -> PortableReading {
        PortableReading(t: minute(m), schemaVersion: 1, seq: m, bootId: "p", qualityFlags: [], pm25: pm, pm10: nil, tempC: 20, rh: 50, session: .window)
    }

    @Test("Minutes above the prompt and the peak come from the readings in the window")
    func summaryCountsMinutesAndPeak() {
        let readings = (0..<5).map { indoor($0, co2: 600) }
            + (5..<8).map { indoor($0, co2: 1200) }
            + [indoor(8, co2: 1500), indoor(9, co2: nil)]
        let summary = Insights.summary(indoor: readings, portable: [], from: start, to: minute(9), co2Trigger: 1000, pm25Trigger: 35.5)
        #expect(summary.minutesAbovePrompt == 4)
        #expect(summary.peakCO2 == 1500)
        #expect(summary.peakCO2At == minute(8))
        #expect(summary.averagePM25 == nil)
    }

    @Test("Outdoor PM2.5 gives an average, a peak, and minutes above the advisory")
    func summaryPM25() {
        let readings = [portable(0, pm: 10), portable(1, pm: 20), portable(2, pm: 40), portable(3, pm: nil)]
        let summary = Insights.summary(indoor: [], portable: readings, from: start, to: minute(3), co2Trigger: 1000, pm25Trigger: 35.5)
        #expect(summary.averagePM25 != nil)
        #expect(abs((summary.averagePM25 ?? 0) - 23.333) < 0.01)
        #expect(summary.peakPM25 == 40)
        #expect(summary.minutesAboveAdvisory == 1)
    }

    @Test("Readings outside the window are ignored")
    func summaryWindow() {
        let readings = [indoor(0, co2: 2000), indoor(10, co2: 600), indoor(20, co2: 2000)]
        let summary = Insights.summary(indoor: readings, portable: [], from: minute(5), to: minute(15), co2Trigger: 1000, pm25Trigger: 35.5)
        #expect(summary.minutesAbovePrompt == 0)
        #expect(summary.peakCO2 == 600)
    }

    @Test("Box health counts what arrived, restarts, and the longest silence")
    func health() {
        let readings = (0..<20).map { indoor($0, co2: 600, boot: "a") } + (40..<60).map { indoor($0, co2: 600, boot: "b") }
        let health = Insights.health(readings, from: start, to: minute(59))
        #expect(health.received == 40)
        #expect(health.expected == 59)
        #expect(health.restarts == 1)
        #expect(health.longestGap == 21.0 * 60)
        #expect(abs(health.share - 40.0 / 59.0) < 0.001)
    }

    @Test("A silent box is a full-window gap, not a clean sheet")
    func healthSilent() {
        let health = Insights.health([] as [IndoorReading], from: start, to: minute(60))
        #expect(health.received == 0)
        #expect(health.share == 0)
        #expect(health.restarts == 0)
        #expect(health.longestGap == 3600.0)
    }

    @Test("A box that kept up has no gap to report")
    func healthClean() {
        let readings = (0...60).map { indoor($0, co2: 600) }
        let health = Insights.health(readings, from: start, to: minute(60))
        #expect(health.share == 1)
        #expect(health.longestGap == nil)
    }

    @Test("Ten-second uploads count as one covered minute, not six")
    func frequentUploads() {
        let readings = (0..<6).map { index in
            IndoorReading(t: start.addingTimeInterval(Double(index * 10)), schemaVersion: 1,
                seq: index, bootId: "b", qualityFlags: [], co2: 1200, tempC: nil, rh: nil)
        }
        let summary = Insights.summary(indoor: readings, portable: [], from: start, to: minute(60), co2Trigger: 1000, pm25Trigger: 35.5)
        #expect(summary.minutesAbovePrompt == 1)
        #expect(Insights.health(readings, from: start, to: minute(60)).received == 1)
    }

    @Test func stats() {
        let stats = Insights.stats([3, 9, 6])
        #expect(stats?.min == 3)
        #expect(stats?.max == 9)
        #expect(stats?.average == 6)
        #expect(Insights.stats([]) == nil)
    }

    @Test func minutesText() {
        #expect(Measure.minutesText(0) == "0 min")
        #expect(Measure.minutesText(45) == "45 min")
        #expect(Measure.minutesText(120) == "2 h")
        #expect(Measure.minutesText(130) == "2 h 10 min")
    }
}
