import SwiftUI

/// The two physical sensor boxes. Weather and regional AQI live in their own tab.
struct NowView: View {
    @Environment(AirStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = PortableLocation()
    @State private var detail: Detail?

    private enum Detail: String, Identifiable {
        case indoor, portable, location, connection, about, family
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connection
                    if store.provenance != .live {
                        Label(store.provenance == .placeholder ? "Preview · Sample readings" : "Recorded readings",
                              systemImage: "play.rectangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    indoorCard
                    portableCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sensors")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { detail = .family } label: { Image(systemName: "person.2") }
                        .accessibilityLabel("Family access")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { detail = .about } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About School Air")
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in location.setForeground(phase == .active) }
            .sheet(item: $detail) { selected in
                switch selected {
                case .location: PortableLocationSheet(location: location).environment(store)
                case .about: AboutView()
                case .family: FamilyAccessView().environment(store)
                default: ReadingDetails(kind: selected.rawValue).environment(store)
                }
            }
        }
    }

    private var connection: some View {
        let hasIssue = !(store.snapshot?.issues.isEmpty ?? true)
        let connected = store.snapshot?.connected == true
        return Button { detail = .connection } label: {
            HStack(spacing: 6) {
                Circle().fill(hasIssue ? Color.orange : connected ? .green : .secondary).frame(width: 6, height: 6)
                Text(hasIssue ? "Connection needs attention" : connected ? "Connected" : store.provenance != .live ? "Preview" : "Connecting…")
                Spacer()
                if hasIssue { Image(systemName: "chevron.right") }
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasIssue ? "Connection needs attention. Show details" : "Connection details")
    }

    private var indoorCard: some View {
        let reading = store.snapshot?.latestIndoor
        return Button { detail = .indoor } label: {
            CompactReadingCard(title: "Indoor CO₂", value: reading?.co2, unit: "ppm", digits: 0,
                               band: reading?.co2.map(CO2Bands.band(for:)), tag: RowTag(status: store.indoorStatus),
                               scale: Scales.co2Range, gradient: Scales.co2, dimmed: !store.indoorStatus.canAdvise,
                               caption: reading.map { "Updated \(store.indoorStatus.canAdvise ? $0.t.clockText : $0.t.dayClockText)" } ?? "Waiting for the indoor box")
        }.buttonStyle(.plain).accessibilityIdentifier("indoorSensor").accessibilityHint("Show readings and sensor history")
    }

    private var portableCard: some View {
        let reading = store.snapshot?.latestPortable
        return VStack(spacing: 0) {
            Button { detail = .portable } label: {
                CompactReadingCard(title: "Portable PM2.5", value: reading?.pm25, unit: "µg/m³", digits: 1,
                                   band: reading?.pm25.map(PM25Bands.band(for:)), tag: RowTag(status: store.portableStatus),
                                   scale: Scales.pm25Range, gradient: Scales.pm25, dimmed: !store.portableStatus.canAdvise,
                                   caption: reading.map { "Updated \(store.portableStatus.canAdvise ? $0.t.clockText : $0.t.dayClockText)" } ?? "Waiting for the portable box",
                                   hasBackground: false)
            }.buttonStyle(.plain).accessibilityIdentifier("portableSensor").accessibilityHint("Show readings and sensor history")
            Divider().padding(.horizontal, 18)
            Button { detail = .location } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location")
                    Text(location.label).lineLimit(2)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .accessibilityIdentifier("portableLocation")
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }


}

struct CompactReadingCard: View {
    let title: String
    let value: Double?
    let unit: String
    let digits: Int
    let band: Band?
    let tag: RowTag
    let scale: ClosedRange<Double>
    let gradient: Gradient
    let dimmed: Bool
    let caption: String
    var hasBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Label(tag.text, systemImage: tag.symbol)
                    .font(.caption.weight(.medium)).foregroundStyle(tag.color)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { number; Spacer(minLength: 10); category }
                VStack(alignment: .leading, spacing: 4) { number; category }
            }
            if let value {
                Gauge(value: min(max(value, scale.lowerBound), scale.upperBound), in: scale) { EmptyView() }
                    .gaugeStyle(.accessoryLinear).tint(gradient).accessibilityHidden(true)
            }
            HStack {
                Text(caption)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hasBackground ? Color(.secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Show measurement details")
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value.map { $0.text(digits) } ?? "—")
                .font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
                .contentTransition(.numericText())
            Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var category: some View {
        if let band, value != nil {
            Text(band.label).font(.caption.weight(.semibold))
                .foregroundStyle(dimmed ? .secondary : band.tone.textColor)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(band.tone.color.opacity(dimmed ? 0.05 : 0.10), in: Capsule())
        }
    }
}

struct ReadingDetails: View {
    @Environment(AirStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: String

    var body: some View {
        NavigationStack {
            List {
                if kind == "indoor" {
                    indoor
                    if store.provenance != .live { ProvenanceSection(provenance: store.provenance) }
                    SensorHistorySection(sensor: .indoor)
                }
                if kind == "portable" {
                    portable
                    if store.provenance != .live { ProvenanceSection(provenance: store.provenance) }
                    SensorHistorySection(sensor: .portable)
                }
                if kind == "regional" { regional }
                if kind == "connection" { connection }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var title: String {
        switch kind {
        case "indoor": "Indoor CO₂"
        case "portable": "Portable PM2.5"
        case "regional": "Outside AQI"
        default: "Connection"
        }
    }

    private var indoor: some View {
        Section {
            LabeledContent("CO₂", value: Measure.text(store.snapshot?.latestIndoor?.co2, unit: "ppm", digits: 0))
            LabeledContent("Temperature", value: Measure.text(store.snapshot?.latestIndoor?.tempC, unit: "°C", digits: 1))
            LabeledContent("Humidity", value: Measure.text(store.snapshot?.latestIndoor?.rh, unit: "%", digits: 0))
            LabeledContent("Status", value: store.indoorStatus.label)
            if let reading = store.snapshot?.latestIndoor { LabeledContent("Measured", value: reading.t.dayClockText) }
            LabeledContent("Sensor", value: "SCD-41")
        } footer: {
            Text(store.indoorStatus.canAdvise ? "CO₂ helps you follow ventilation in the room. Colors are ventilation prompts, not health ratings." : "The indoor box needs a current reading. Check its power, Wi-Fi and cloud status.")
        }
    }

    private var portable: some View {
        Section {
            LabeledContent("PM2.5", value: Measure.text(store.snapshot?.latestPortable?.pm25, unit: "µg/m³", digits: 1))
            LabeledContent("PM10", value: Measure.text(store.snapshot?.latestPortable?.pm10, unit: "µg/m³", digits: 1))
            LabeledContent("Temperature", value: Measure.text(store.snapshot?.latestPortable?.tempC, unit: "°C", digits: 1))
            LabeledContent("Humidity", value: Measure.text(store.snapshot?.latestPortable?.rh, unit: "%", digits: 0))
            LabeledContent("Status", value: store.portableStatus.label)
            if let reading = store.snapshot?.latestPortable { LabeledContent("Measured", value: reading.t.dayClockText) }
            LabeledContent("Sensor", value: "PMSA003I + SHT45")
        } footer: {
            Text("Particles measured where the box sits. This is the raw environmental concentration, not an AQI or a humidity-corrected value. The saved box location is set by standing next to it; update that spot whenever you move the box.")
        }
    }

    @ViewBuilder private var regional: some View {
        if let report = store.regional {
            Section {
                LabeledContent("US AQI", value: String(report.aqi))
                LabeledContent("Category", value: report.categoryName)
                LabeledContent("Area", value: "\(report.reportingArea), \(report.stateCode)")
                LabeledContent("Valid", value: report.observed.dayClockText)
                LabeledContent("Source", value: report.sourceLabel)
                if let pm = report.pm25 { LabeledContent("Modeled PM2.5", value: Measure.text(pm, unit: "µg/m³", digits: 1)) }
            }
            if report.isModeled { modelExplanation }
        } else if store.airNow.label.contains("Open-Meteo") { modelExplanation }
        if let error = store.regionalError { Section { Text(error).font(.subheadline) } }
        Section { Button("Refresh report") { Task { await store.refreshRegional() } } }
    }

    private var modelExplanation: some View {
        Section("What does Estimate mean?") {
            Text("A regional air-quality model estimates pollution across the area. It is not a reading from your portable box or a nearby monitoring station.")
            Text("This report is for Evansville. It stays separate from your phone location. CAMS uses a grid of about 45 km; particle AQI uses a 24-hour modeled average.")
                .font(.subheadline).foregroundStyle(.secondary)
            Link("Open-Meteo air-quality data", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
            Link("CAMS atmospheric forecasts", destination: URL(string: "https://atmosphere.copernicus.eu/")!)
        }
    }

    private var connection: some View {
        Section {
            LabeledContent("Firebase", value: store.snapshot?.connected == true ? "Connected" : "Connecting")
            LabeledContent("Indoor box", value: store.indoorStatus.label)
            LabeledContent("Portable box", value: store.portableStatus.label)
            ForEach((store.snapshot?.issues ?? [:]).keys.sorted(), id: \.self) { key in
                Text(store.snapshot?.issues[key] ?? "").foregroundStyle(.orange)
            }
            Button("Retry connection") { store.connectionAttempt += 1 }
        } footer: {
            Text("A box becomes stale after three minutes without a new reading. Previous measurements stay visible.")
        }
    }
}

private struct PortableLocationSheet: View {
    @Bindable var location: PortableLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Stand next to your portable box, then save this spot.")
                    Button {
                        location.saveNearbyLocation()
                    } label: {
                        Label(location.isLocating ? "Saving location…" : "The box is next to me", systemImage: "mappin.and.ellipse")
                    }
                    .disabled(location.isLocating)
                    .accessibilityIdentifier("saveBoxLocation")
                    if location.isLocating {
                        HStack { ProgressView(); Text("Getting a fresh location") }
                        Button("Cancel") { location.cancelCapture() }
                    }
                    if let message = location.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if location.needsSettings {
                        Button("Open Location Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                } footer: {
                    Text("Your phone is used once to mark the box’s position. This spot stays saved when you walk away or close the app. Use the button again after moving the box.")
                }
                if let saved = location.saved {
                    Section("Saved box location") {
                        if let place = saved.place { LabeledContent("Place", value: place) }
                        LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", saved.fix.latitude, saved.fix.longitude))
                        LabeledContent("Accuracy", value: "About \(Int(saved.fix.accuracy.rounded())) m")
                        LabeledContent("Saved", value: saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                        Button("Clear saved location", role: .destructive) { location.clearSavedLocation() }
                    }
                }
                Section {
                    Text("Saved on this phone only. No background tracking and no coordinates sent to Firebase. Apple supplies the nearby place name. Past sensor readings are unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Box location").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview { NowView().environment(AirStore.preview) }
