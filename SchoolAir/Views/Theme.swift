import SwiftUI
import Charts

extension Tone {
    /// Fill color for dots, gauges and icon backgrounds. System colors so dark mode is free.
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .maroon: Color(red: 0.55, green: 0.12, blue: 0.25)
        case .gray: Color(.systemGray)
        }
    }

    /// Text color. Yellow is unreadable as text on a light background, so it darkens to amber.
    var textColor: Color {
        switch self {
        case .yellow: Color(red: 0.72, green: 0.52, blue: 0.0)
        case .gray: Color(.secondaryLabel)
        default: color
        }
    }
}

/// The gradient bars under each big number, with color stops at the real thresholds.
enum Scales {
    static let co2Range: ClosedRange<Double> = 400...2000
    static let co2 = Gradient(stops: [
        .init(color: .green, location: 0.0),
        .init(color: .yellow, location: 0.25),      // 800 ppm
        .init(color: .orange, location: 0.375),     // 1,000 ppm
        .init(color: .red, location: 0.6875),       // 1,500 ppm
        .init(color: .red, location: 1.0),
    ])

    static let pm25Range: ClosedRange<Double> = 0...150
    static let pm25 = Gradient(stops: [
        .init(color: .green, location: 0.0),
        .init(color: .yellow, location: 0.06),      // 9.0 µg/m³
        .init(color: .orange, location: 0.237),     // 35.5
        .init(color: .red, location: 0.37),         // 55.5
        .init(color: .purple, location: 0.837),     // 125.5
        .init(color: .purple, location: 1.0),
    ])

    static let aqiRange: ClosedRange<Double> = 0...300
    static let aqi = Gradient(stops: [
        .init(color: .green, location: 0.0),
        .init(color: .yellow, location: 0.167),     // 50
        .init(color: .orange, location: 0.333),     // 100
        .init(color: .red, location: 0.5),          // 150
        .init(color: .purple, location: 0.667),     // 200
        .init(color: Tone.maroon.color, location: 1.0),
    ])
}

/// A small trailing label on a reading row: the box's status, or "Placeholder".
struct RowTag {
    let text: String
    let symbol: String
    let color: Color
    let isLive: Bool

    init(text: String, symbol: String, color: Color) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.isLive = false
    }

    init(status: BoxStatus) {
        text = status.label
        symbol = status.symbol
        color = status.tone.textColor
        isLive = status == .live
    }
}

/// "Live" with the radio waves rippling and the text breathing, so a fresh box is unmistakable.
struct LiveBadge: View {
    var body: some View {
        Label("Live", systemImage: "dot.radiowaves.left.and.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.green)
        .accessibilityLabel("Live")
    }
}

/// The hero row of a section: a big rounded number, its unit, its band, a gauge, and a footnote.
struct ReadingRow: View {
    let title: String
    let value: Double?
    let unit: String
    let digits: Int
    let band: Band?
    let footnote: String
    let tag: RowTag?
    let scale: ClosedRange<Double>
    let gradient: Gradient
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let tag {
                    if tag.isLive {
                        LiveBadge()
                    } else {
                        Label(tag.text, systemImage: tag.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(tag.color)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { $0.text(digits) } ?? "No data")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(dimmed || value == nil ? .secondary : .primary)
                if value != nil {
                    Text(unit)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let band, value != nil {
                    HStack(spacing: 6) {
                        Circle().fill(band.tone.color).frame(width: 8, height: 8)
                        Text(band.label).font(.subheadline.weight(.medium))
                    }
                }
            }

            if let value {
                Gauge(value: min(max(value, scale.lowerBound), scale.upperBound), in: scale) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(gradient)
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityElement(children: .combine)
    }
}

/// Says, every time, when the numbers are not live.
struct ProvenanceSection: View {
    let provenance: AirSnapshot.Provenance

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .listRowBackground(tint.opacity(0.1))
        }
    }

    private var title: String {
        provenance == .recorded ? "Recorded data" : "Placeholder data"
    }

    private var detail: String {
        provenance == .recorded
            ? "A replay, not the air right now."
            : "Sample readings for preview. Not live sensor data."
    }

    private var symbol: String {
        provenance == .recorded ? "recordingtape" : "hammer.fill"
    }

    private var tint: Color {
        provenance == .recorded ? .orange : .purple
    }
}

struct DisclaimerFooter: View {
    var body: some View {
        Text("Colors and prompts are product choices, not validated health thresholds.")
    }
}

/// A tiny trend line with no axes, for a list row.
struct Sparkline: View {
    let series: HistorySeries
    let color: Color

    var body: some View {
        Chart(series.points) { point in
            LineMark(
                x: .value("Time", point.t),
                y: .value("Value", point.value),
                series: .value("Segment", point.segment)
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

struct SparklineRow: View {
    let title: String
    let series: HistorySeries
    let color: Color

    var body: some View {
        LabeledContent(title) {
            if series.points.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                Sparkline(series: series, color: color)
                    .frame(width: 132, height: 30)
            }
        }
    }
}

/// Min · Avg · Max style figures in a row, like the summary under a Health chart.
struct StatStrip: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

