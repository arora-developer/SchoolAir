import SwiftUI
import Charts

enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24 hours"
    case week = "7 days"

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        }
    }

    /// Bound rendering to 288 day points or 336 week points per chart.
    var bucket: TimeInterval? {
        switch self {
        case .day: 5 * 60
        case .week: 30 * 60
        }
    }

    /// Added to the "Latest" caption so a smoothed number is never mistaken for a raw one.
    var captionSuffix: String {
        switch self {
        case .day: " · 5-min average"
        case .week: " · 30-min average"
        }
    }
}

struct ChartGuide: Identifiable, Hashable {
    var value: Double
    var label: String
    var tone: Tone
    var id: Double { value }
}

extension ChartGuide {
    static func forSensor(_ sensor: NodeKind, thresholds t: AdvisoryEngine.Thresholds) -> [ChartGuide] {
        switch sensor {
        case .indoor:
            [ChartGuide(value: 800, label: "", tone: .yellow),
             ChartGuide(value: t.co2Trigger, label: "Prompt \(t.co2Trigger.text(0))", tone: .orange),
             ChartGuide(value: 1500, label: "", tone: .red)]
        case .portable:
            [ChartGuide(value: 9, label: "", tone: .green),
             ChartGuide(value: t.pm25Trigger, label: "Advisory \(t.pm25Trigger.text(1))", tone: .orange),
             ChartGuide(value: 55.5, label: "", tone: .red)]
        }
    }
}

/// Charts the last 24 hours and 7 days, with the gaps left visible and event markers added by hand.
struct HistoryView: View {
    @Environment(AirStore.self) private var store
    /// Launch with `-range week` to open on the seven-day view (screenshots, demos).
    @State private var range: HistoryRange = UserDefaults.standard.string(forKey: "range") == "week" ? .week : .day
    @State private var showAddEvent = false
    @State private var display: HistoryDisplay?
    private var refreshKey: String {
        "\(range.rawValue)-\(store.snapshot?.receivedAt.timeIntervalSince1970 ?? 0)-\(Int(store.now.timeIntervalSince1970 / 60))"
    }

    private var window: ClosedRange<Date> {
        display?.window ?? store.now.addingTimeInterval(-range.duration)...store.now
    }

    var body: some View {
        let co2 = display?.co2 ?? .empty
        let pm25 = display?.pm25 ?? .empty
        let summary = display?.summary
        let co2Stats = display?.co2Stats
        let pmStats = display?.pmStats
        let indoorEvents = events(for: Node.indoorID)
        let portableEvents = events(for: Node.portableID)

        NavigationStack {
            List {
                if display == nil { ProgressView("Preparing history…") }

                Section {
                    Picker("Range", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if store.provenance != .live {
                    ProvenanceSection(provenance: store.provenance)
                }

                Section {
                    ChartRow(unit: "ppm", digits: 0, series: co2, guides: co2Guides, events: indoorEvents, window: window, range: range, color: .accentColor, stats: co2Stats)
                } header: {
                    Text("CO2 in the room")
                } footer: {
                    Text(footer(above: summary?.minutesAbovePrompt ?? 0, what: "above the prompt", series: co2))
                }

                Section {
                    ChartRow(unit: "µg/m³", digits: 1, series: pm25, guides: pmGuides, events: portableEvents, window: window, range: range, color: .indigo, stats: pmStats)
                } header: {
                    Text("Portable PM2.5")
                } footer: {
                    Text(footer(above: summary?.minutesAboveAdvisory ?? 0, what: "above the advisory", series: pm25))
                }

                Section {
                    if eventsInWindow.isEmpty {
                        Text("No events in this range")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(eventsInWindow) { event in
                        EventRow(event: event)
                            .deleteDisabled(event.isPlaceholder)
                    }
                    .onDelete(perform: delete)
                    Button {
                        showAddEvent = true
                    } label: {
                        Label("Add Event Marker", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Event markers")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add event marker")
                }
            }
            .task(id: refreshKey) {
                let snapshot = store.snapshot
                let end = store.now
                let start = end.addingTimeInterval(-range.duration)
                let bucket = range.bucket
                let co2Trigger = store.thresholds.co2Trigger
                let pmTrigger = store.thresholds.pm25Trigger
                let task = Task.detached(priority: .userInitiated) {
                    HistoryDisplay.build(snapshot: snapshot, start: start, end: end, bucket: bucket,
                                         co2Trigger: co2Trigger, pmTrigger: pmTrigger)
                }
                let next = await withTaskCancellationHandler {
                    await task.value
                } onCancel: { task.cancel() }
                guard !Task.isCancelled else { return }
                display = next
            }
            .onChange(of: range) { _, newValue in
                display = nil
                UserDefaults.standard.set(newValue == .week ? "week" : "day", forKey: "range")
            }
            .sheet(isPresented: $showAddEvent) {
                AddEventSheet { store.events.add($0) }
            }
        }
    }

    private var eventsInWindow: [EventMarker] {
        store.allEvents.filter { window.contains($0.at) }
    }

    private func events(for nodeId: String) -> [EventMarker] {
        eventsInWindow.filter { $0.nodeId == nil || $0.nodeId == nodeId || ($0.nodeId == "home-portable" && nodeId == Node.portableID) }
    }

    private func delete(at offsets: IndexSet) {
        let visible = eventsInWindow
        for index in offsets where !visible[index].isPlaceholder {
            store.events.remove(visible[index])
        }
    }

    /// Time over the line, plus a note whenever there is a hole in the data. Gaps are never filled in.
    private func footer(above minutes: Int, what: String, series: HistorySeries) -> String {
        var parts = ["\(Measure.minutesText(minutes)) \(what)"]
        if !series.gaps.isEmpty {
            parts.append(series.gaps.count == 1 ? "1 gap shown in gray" : "\(series.gaps.count) gaps shown in gray")
        }
        return parts.joined(separator: " · ")
    }

    private var co2Guides: [ChartGuide] { ChartGuide.forSensor(.indoor, thresholds: store.thresholds) }
    private var pmGuides: [ChartGuide] { ChartGuide.forSensor(.portable, thresholds: store.thresholds) }

}

// MARK: - Chart

struct ChartRow: View {
    let unit: String
    let digits: Int
    let series: HistorySeries
    let guides: [ChartGuide]
    let events: [EventMarker]
    let window: ClosedRange<Date>
    let range: HistoryRange
    let color: Color
    let stats: Insights.Stats?

    @State private var selectedTime: Date?

    private var selected: HistorySeries.Point? {
        selectedTime.flatMap(series.nearest(to:))
    }

    private var shown: HistorySeries.Point? {
        selected ?? series.points.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text((selected == nil ? "Latest" : "Selected") + range.captionSuffix)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let shown {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(shown.value.text(digits))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(shown.t.dayClockText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if series.points.isEmpty {
                ContentUnavailableView {
                    Label("No readings in this range", systemImage: "chart.line.downtrend.xyaxis")
                } description: {
                    Text("Gaps stay gaps. Nothing is filled in.")
                }
                .frame(height: 180)
            } else {
                chart.frame(height: 200)
            }

            if let stats {
                StatStrip(items: [
                    .init(label: "Min", value: "\(stats.min.text(digits)) \(unit)"),
                    .init(label: "Avg", value: "\(stats.average.text(digits)) \(unit)"),
                    .init(label: "Max", value: "\(stats.max.text(digits)) \(unit)"),
                ])
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private var chart: some View {
        Chart {
            ForEach(series.gaps) { gap in
                RectangleMark(
                    xStart: .value("Gap start", gap.start),
                    xEnd: .value("Gap end", gap.end)
                )
                .foregroundStyle(Color(.systemFill))
            }

            ForEach(guides) { guide in
                RuleMark(y: .value(unit, guide.value))
                    .foregroundStyle(guide.tone.color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        if !guide.label.isEmpty {
                            Text(guide.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(guide.tone.textColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                                .overlay(Capsule().strokeBorder(guide.tone.color.opacity(0.5), lineWidth: 1))
                        }
                    }
            }

            ForEach(series.points) { point in
                LineMark(
                    x: .value("Time", point.t),
                    y: .value(unit, point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(color)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(events) { event in
                RuleMark(x: .value("Event", event.at))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    // Overlay keeps the badge inside the plot, so it never spills into the header above.
                    .annotation(position: .overlay, alignment: .top, spacing: 0) {
                        Image(systemName: event.kind.symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                            .overlay(Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1))
                    }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.t))
                    .foregroundStyle(Color(.secondaryLabel))
                PointMark(x: .value("Time", selected.t), y: .value(unit, selected.value))
                    .foregroundStyle(color)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: window)
        .chartXSelection(value: $selectedTime)
        .chartXAxis {
            switch range {
            case .day:
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(), centered: false,
                                   anchor: value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top)
                }
            case .week:
                AxisMarks(values: .stride(by: .day, count: 1)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: false,
                                   anchor: value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top)
                }
            }
        }
        .accessibilityLabel("\(unit) chart")
    }
}

// MARK: - Events

struct EventRow: View {
    let event: EventMarker

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: event.kind.symbol)
                .foregroundStyle(Color.accentColor)
        }
    }

    private var detail: String {
        let which: String
        switch event.nodeId {
        case Node.indoorID: which = "Indoor box"
        case Node.portableID, "home-portable": which = "Portable box"
        case .some(let other): which = other
        case .none: which = "Room"
        }
        var text = "\(which) · \(event.at.dayClockText)"
        if event.isPlaceholder { text += " · Placeholder" }
        return text
    }
}

struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (EventMarker) -> Void

    @State private var kind: EventKind = .hvacChanged
    @State private var scope: Scope = .room
    @State private var at = Date()
    @State private var note = ""

    enum Scope: String, CaseIterable, Identifiable {
        case room = "Room"
        case indoor = "Indoor box"
        case portable = "Portable box"

        var id: String { rawValue }

        var nodeId: String? {
            switch self {
            case .room: nil
            case .indoor: Node.indoorID
            case .portable: Node.portableID
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What changed") {
                    Picker("Event", selection: $kind) {
                        ForEach(EventKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Picker("Applies to", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("When") {
                    DatePicker("Time", selection: $at, in: ...Date())
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Add Event Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EventMarker(
                            kind: kind,
                            at: at,
                            nodeId: scope.nodeId,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    HistoryView()
        .environment(AirStore.preview)
}
