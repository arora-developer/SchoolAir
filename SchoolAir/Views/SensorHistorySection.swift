import SwiftUI

/// Embedded in a sensor's detail sheet; the separate History tab stays available.
struct SensorHistorySection: View {
    @Environment(AirStore.self) private var store
    let sensor: NodeKind
    @State private var range: HistoryRange = .day
    @State private var display: SensorHistoryDisplay?
    @State private var preparedRange: HistoryRange = .day

    private var refreshKey: String {
        "\(sensor.rawValue)-\(range.rawValue)-\(store.snapshot?.receivedAt.timeIntervalSince1970 ?? 0)-\(Int(store.now.timeIntervalSince1970 / 60))"
    }
    private var issue: String? {
        store.snapshot?.issues[sensor == .indoor ? "Indoor history" : "Portable history"]
    }

    var body: some View {
        Section {
            Picker("History range", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sensorHistoryRange")

            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            } else if let display {
                ChartRow(unit: sensor == .indoor ? "ppm" : "µg/m³",
                         digits: sensor == .indoor ? 0 : 1,
                         series: display.series,
                         guides: ChartGuide.forSensor(sensor, thresholds: store.thresholds),
                         events: SensorHistoryDisplay.events(store.allEvents, for: sensor, in: display.window),
                         window: display.window, range: preparedRange,
                         color: sensor == .indoor ? .accentColor : .indigo,
                         stats: display.stats)
                    .id(preparedRange)
                    .accessibilityIdentifier("\(sensor.rawValue)HistoryChart")
            } else {
                ProgressView("Preparing history…")
            }
        } header: {
            Text(sensor == .indoor ? "CO₂ history" : "PM2.5 history")
        } footer: {
            if issue == nil {
                Text("Drag across the chart to explore. Gray areas mark missing readings.")
            }
        }
        .task(id: refreshKey) {
            let requestedRange = range
            let snapshot = store.snapshot
            let end = store.now
            let start = end.addingTimeInterval(-range.duration)
            let bucket = range.bucket
            let kind = sensor
            let task = Task.detached(priority: .userInitiated) {
                SensorHistoryDisplay.build(snapshot: snapshot, sensor: kind, start: start, end: end, bucket: bucket)
            }
            let next = await withTaskCancellationHandler {
                await task.value
            } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            display = next
            preparedRange = requestedRange
        }
    }
}
