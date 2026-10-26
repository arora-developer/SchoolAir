import Foundation

/// Only the tapped box is processed. Chart averaging and gaps match the History tab.
struct SensorHistoryDisplay: Sendable {
    let window: ClosedRange<Date>
    let series: HistorySeries
    let stats: Insights.Stats?

    static func build(snapshot: AirSnapshot?, sensor: NodeKind, start: Date, end: Date,
                      bucket: TimeInterval?) -> SensorHistoryDisplay {
        let samples: [(Date, Double?)]
        switch sensor {
        case .indoor: samples = (snapshot?.indoorHistory ?? []).map { ($0.t, $0.co2) }
        case .portable: samples = (snapshot?.portableHistory ?? []).map { ($0.t, $0.pm25) }
        }
        let visible = samples.filter { $0.0 >= start && $0.0 <= end }
        return SensorHistoryDisplay(
            window: start...end,
            series: HistorySeries.build(samples: visible, from: start, to: end, bucket: bucket),
            stats: Insights.stats(visible.compactMap { $0.1 }.filter(\.isFinite)))
    }

    static func events(_ events: [EventMarker], for sensor: NodeKind, in window: ClosedRange<Date>) -> [EventMarker] {
        let nodeID = sensor == .indoor ? Node.indoorID : Node.portableID
        return events.filter {
            window.contains($0.at) && ($0.nodeId == nil || $0.nodeId == nodeID ||
                (sensor == .portable && $0.nodeId == "home-portable"))
        }
    }
}
