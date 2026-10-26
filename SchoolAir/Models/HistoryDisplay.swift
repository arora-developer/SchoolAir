import Foundation

/// Prepared off the main thread; SwiftUI reads finished values rather than rescanning history.
struct HistoryDisplay: Sendable {
    let window: ClosedRange<Date>
    let co2: HistorySeries
    let pm25: HistorySeries
    let summary: Insights.Summary
    let co2Stats: Insights.Stats?
    let pmStats: Insights.Stats?

    static func build(snapshot: AirSnapshot?, start: Date, end: Date, bucket: TimeInterval?,
                      co2Trigger: Double, pmTrigger: Double) -> HistoryDisplay {
        let indoor = (snapshot?.indoorHistory ?? []).filter { $0.t >= start && $0.t <= end }
        let portable = (snapshot?.portableHistory ?? []).filter { $0.t >= start && $0.t <= end }
        return HistoryDisplay(window: start...end,
            co2: HistorySeries.build(samples: indoor.map { ($0.t, $0.co2) }, from: start, to: end, bucket: bucket),
            pm25: HistorySeries.build(samples: portable.map { ($0.t, $0.pm25) }, from: start, to: end, bucket: bucket),
            summary: Insights.summary(indoor: indoor, portable: portable, from: start, to: end,
                                      co2Trigger: co2Trigger, pm25Trigger: pmTrigger),
            co2Stats: Insights.stats(indoor.compactMap(\.co2)),
            pmStats: Insights.stats(portable.compactMap(\.pm25)))
    }
}
