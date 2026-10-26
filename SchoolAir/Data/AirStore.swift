import Foundation
import Observation

/// The app's single source of truth for the screens.
///
/// Consumes snapshots from a `ReadingSource`, polls AirNow, keeps a clock ticking so "stale"
/// ages update, and runs the advisory engine whenever any of that changes.
@MainActor @Observable
final class AirStore {
    private(set) var snapshot: AirSnapshot?
    private(set) var regional: RegionalAQI?
    private(set) var regionalError: String?
    private(set) var advisory: Advisory
    /// Refreshed every few seconds so ages and stale states move without new data.
    private(set) var now = Date()
    /// People in the room, typed in by whoever runs it. 0 means "not set".
    private(set) var occupancy: Int

    let events: EventStore
    let readingSource: any ReadingSource
    let airNow: any AirNowProviding

    var connectionAttempt = 0
    private var refreshingRegional = false
    private var engine: AdvisoryEngine
    private static let occupancyKey = "occupancy"

    init(
        readings: any ReadingSource,
        airNow: any AirNowProviding,
        events: EventStore,
        thresholds: AdvisoryEngine.Thresholds = .v1
    ) {
        self.readingSource = readings
        self.airNow = airNow
        self.events = events
        self.engine = AdvisoryEngine(thresholds: thresholds)
        self.occupancy = UserDefaults.standard.integer(forKey: AirStore.occupancyKey)
        var starter = AdvisoryEngine(thresholds: thresholds)
        self.advisory = starter.evaluate(AdvisoryEngine.Input(
            co2: nil, co2Status: .missing, outdoorPM25: nil, outdoorStatus: .missing,
            outdoorSession: .unknown, occupancy: nil
        ))
    }

    // MARK: Derived state

    var indoorStatus: BoxStatus { BoxStatus.evaluate(snapshot?.latestIndoor, now: now) }
    var portableStatus: BoxStatus { BoxStatus.evaluate(snapshot?.latestPortable, now: now) }
    var provenance: AirSnapshot.Provenance { snapshot?.provenance ?? .live }
    var thresholds: AdvisoryEngine.Thresholds { engine.thresholds }

    /// Placeholder or recorded markers first, then the ones people added. Sorted by time.
    var allEvents: [EventMarker] {
        ((snapshot?.placeholderEvents ?? []) + events.events).sorted { $0.at < $1.at }
    }

    func co2Series(from start: Date, to end: Date, bucket: TimeInterval?) -> HistorySeries {
        HistorySeries.build(
            samples: (snapshot?.indoorHistory ?? []).map { ($0.t, $0.co2) },
            from: start, to: end, bucket: bucket
        )
    }

    func pm25Series(from start: Date, to end: Date, bucket: TimeInterval?) -> HistorySeries {
        HistorySeries.build(
            samples: (snapshot?.portableHistory ?? []).map { ($0.t, $0.pm25) },
            from: start, to: end, bucket: bucket
        )
    }

    // MARK: Insights

    var startOfToday: Date { Calendar.current.startOfDay(for: now) }

    func summary(from start: Date, to end: Date) -> Insights.Summary {
        Insights.summary(
            indoor: snapshot?.indoorHistory ?? [],
            portable: snapshot?.portableHistory ?? [],
            from: start, to: end,
            co2Trigger: thresholds.co2Trigger,
            pm25Trigger: thresholds.pm25Trigger
        )
    }

    var todaySummary: Insights.Summary { summary(from: startOfToday, to: now) }

    /// Last 24 hours, one reading expected per minute.
    var indoorHealth: Insights.BoxHealth {
        Insights.health(snapshot?.indoorHistory ?? [], from: now.addingTimeInterval(-86_400), to: now)
    }

    var portableHealth: Insights.BoxHealth {
        Insights.health(snapshot?.portableHistory ?? [], from: now.addingTimeInterval(-86_400), to: now)
    }

    /// Five-minute averages over the last few hours, for the sparklines.
    func recentCO2(hours: Double = 3) -> HistorySeries {
        co2Series(from: now.addingTimeInterval(-hours * 3600), to: now, bucket: 5 * 60)
    }

    func recentPM25(hours: Double = 3) -> HistorySeries {
        pm25Series(from: now.addingTimeInterval(-hours * 3600), to: now, bucket: 5 * 60)
    }

    func co2Stats(from start: Date, to end: Date) -> Insights.Stats? {
        Insights.stats((snapshot?.indoorHistory ?? []).filter { $0.t >= start && $0.t <= end }.compactMap(\.co2))
    }

    func pm25Stats(from start: Date, to end: Date) -> Insights.Stats? {
        Insights.stats((snapshot?.portableHistory ?? []).filter { $0.t >= start && $0.t <= end }.compactMap(\.pm25))
    }

    // MARK: Actions

    func reconnectSensors() {
        snapshot = nil
        refreshAdvisory()
        connectionAttempt += 1
    }

    func setOccupancy(_ people: Int) {
        occupancy = max(0, people)
        UserDefaults.standard.set(occupancy, forKey: AirStore.occupancyKey)
        refreshAdvisory()
    }

    /// Runs until the owning view goes away. Call from `.task`.
    func start() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.consumeReadings() }
            group.addTask { await self.pollRegional() }
            group.addTask { await self.tick() }
        }
    }

    func refreshRegional() async {
        guard !refreshingRegional else { return }
        refreshingRegional = true
        defer { refreshingRegional = false }
        do {
            regional = try await airNow.currentObservation()
            regionalError = regional == nil ? "No regional report is available right now." : nil
        } catch {
            regionalError = error.localizedDescription
        }
    }

    func refreshAdvisory() {
        let input = AdvisoryEngine.Input(
            co2: snapshot?.latestIndoor?.co2,
            co2Status: indoorStatus,
            outdoorPM25: snapshot?.latestPortable?.pm25,
            outdoorStatus: portableStatus,
            outdoorSession: snapshot?.latestPortable?.session ?? .unknown,
            occupancy: occupancy > 0 ? occupancy : nil
        )
        advisory = engine.evaluate(input)
    }

    // MARK: Loops

    private func consumeReadings() async {
        for await next in readingSource.snapshots() {
            snapshot = next
            
            now = Date()
            refreshAdvisory()
        }
    }

    private func pollRegional() async {
        while !Task.isCancelled {
            await refreshRegional()
            try? await Task.sleep(for: .seconds(10 * 60))
        }
    }

    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            now = Date()
            refreshAdvisory()
        }
    }
}

extension AirStore {
    /// For Xcode previews: placeholder everything, events kept out of the real file.
    static var preview: AirStore {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("preview-events.json")
        return AirStore(readings: PlaceholderReadingSource(), airNow: PlaceholderAirNow(), events: EventStore(fileURL: temp))
    }
}
