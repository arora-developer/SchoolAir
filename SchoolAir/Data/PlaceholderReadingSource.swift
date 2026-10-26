import Foundation

/// Made-up readings so the screens can be built before the boxes exist.
///
/// Everything it emits is marked `.placeholder` and the UI says so. Replace it with
/// `FirebaseReadingSource` in `SchoolAirApp` once the boxes post real data.
final class PlaceholderReadingSource: ReadingSource {
    let label = "Placeholder"
    private let tick: Duration

    init(tick: Duration = .seconds(15)) {
        self.tick = tick
    }

    func snapshots() -> AsyncStream<AirSnapshot> {
        AsyncStream { continuation in
            let task = Task { [tick] in
                var world = PlaceholderWorld(now: Date())
                continuation.yield(world.snapshot())
                while !Task.isCancelled {
                    try? await Task.sleep(for: tick)
                    guard !Task.isCancelled else { break }
                    world.advance(to: Date())
                    continuation.yield(world.snapshot())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Deterministic random numbers so placeholder screens look the same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Roughly bell-shaped noise, mostly within −1…1.
    mutating func noise() -> Double {
        let a = Double.random(in: -1...1, using: &self)
        let b = Double.random(in: -1...1, using: &self)
        let c = Double.random(in: -1...1, using: &self)
        return (a + b + c) / 2
    }
}

/// A made-up week with the shapes we expect to see in the home pilot:
/// a bedroom filling with CO2 overnight, a smoky afternoon, a 40-minute Wi-Fi outage,
/// a reboot with warm-up readings, and a walk to the porch with the portable box.
struct PlaceholderWorld {
    static let nodes: [Node] = [
        Node(id: Node.indoorID, name: "Indoor box", kind: .indoor, location: "Bedroom, door shut", schemaVersion: 1),
        Node(id: Node.portableID, name: "Portable box", kind: .portable, location: "Home, by the bedroom window", schemaVersion: 1),
    ]

    private(set) var indoor: [IndoorReading] = []
    private(set) var portable: [PortableReading] = []
    private(set) var events: [EventMarker] = []

    private let calendar = Calendar.current
    private var rng = SeededGenerator(seed: 2026)
    /// The minute the world was created. History runs up to here; new minutes are appended after it.
    private let demoEnd: Date
    private var lastMinute: Date
    private var indoorBoot = "boot-a1f3"
    private var indoorSeq = 0
    private var portableBoot = "boot-7c02"
    private var portableSeq = 0
    private var co2Wander = 0.0
    private var pmWander = 0.0

    private let wifiOutage: ClosedRange<Date>
    private let rebootAt: Date
    private let smoke: ClosedRange<Date>
    private let porchRun: ClosedRange<Date>

    init(now: Date, days: Int = 7) {
        let minuteNow = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        demoEnd = minuteNow
        let cal = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: minuteNow) ?? minuteNow
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        wifiOutage = at(-5, 13, 10)...at(-5, 13, 50)
        rebootAt = at(-2, 9, 0)
        smoke = at(-4, 14, 0)...at(-4, 19, 0)
        porchRun = at(-1, 16, 0)...at(-1, 16, 40)
        events = [
            EventMarker(kind: .windowOpened, at: at(-6, 8, 5), nodeId: Node.indoorID, note: "Bedroom window opened after the night", isPlaceholder: true),
            EventMarker(kind: .hepaOn, at: at(-4, 15, 30), nodeId: nil, note: "Portable HEPA on during the smoky afternoon", isPlaceholder: true),
            EventMarker(kind: .hvacChanged, at: at(-3, 10, 0), nodeId: Node.indoorID, note: "Outdoor-air damper raised one notch", isPlaceholder: true),
            EventMarker(kind: .boxMoved, at: at(-1, 16, 0), nodeId: Node.portableID, note: "Carried to the porch for a run", isPlaceholder: true),
        ]
        let start = cal.date(byAdding: .day, value: -days, to: minuteNow) ?? minuteNow
        lastMinute = start.addingTimeInterval(-60)
        advance(to: minuteNow)
    }

    func snapshot() -> AirSnapshot {
        AirSnapshot(
            nodes: Self.nodes,
            latestIndoor: indoor.last,
            latestPortable: portable.last,
            indoorHistory: indoor,
            portableHistory: portable,
            placeholderEvents: events,
            provenance: .placeholder,
            receivedAt: Date()
        )
    }

    /// Append one reading per whole minute that has passed, then drop anything older than a week.
    mutating func advance(to now: Date) {
        let target = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        while lastMinute.addingTimeInterval(60) <= target {
            appendMinute(at: lastMinute.addingTimeInterval(60))
        }
        let cutoff = target.addingTimeInterval(-7 * 86_400 - 3600)
        indoor.removeAll { $0.t < cutoff }
        portable.removeAll { $0.t < cutoff }
    }

    private mutating func appendMinute(at t: Date) {
        lastMinute = t

        // Wi-Fi pulled: the boxes keep measuring (seq keeps counting) but nothing arrives. The gap stays a gap.
        if wifiOutage.contains(t) {
            indoorSeq += 1
            portableSeq += 1
            return
        }
        if t == rebootAt {
            indoorBoot = "boot-4e9b"
            indoorSeq = 0
        }

        let h = hourOfDay(t)

        // Indoor box: SCD-41.
        co2Wander = co2Wander * 0.92 + rng.noise() * 10
        var indoorFlags: [QualityFlag] = []
        var co2: Double? = (co2Target(at: t, hour: h) + co2Wander).rounded()
        if indoorSeq < 2 {
            indoorFlags = [.warmingUp]
            co2 = nil
        }
        let indoorTemp = 22.3 + 0.8 * sin((h - 10) / 24 * 2 * .pi) + rng.noise() * 0.05
        let indoorRH = 44 + 3 * sin((h - 4) / 24 * 2 * .pi) + rng.noise() * 0.4
        indoor.append(IndoorReading(
            t: t, schemaVersion: 1, seq: indoorSeq, bootId: indoorBoot, qualityFlags: indoorFlags,
            co2: co2, tempC: round1(indoorTemp), rh: indoorRH.rounded()
        ))
        indoorSeq += 1

        // Portable box: PMSA003I + SHT45.
        pmWander = pmWander * 0.9 + rng.noise() * 0.7
        var portableFlags: [QualityFlag] = []
        var pm25: Double? = round1(max(0.3, pmTarget(at: t, hour: h) + pmWander))
        var pm10: Double? = pm25.map { round1($0 * 1.55 + abs(rng.noise()) * 1.2) }
        if portableSeq < 1 {
            portableFlags = [.warmingUp]
            pm25 = nil
            pm10 = nil
        }
        let outdoorTemp = 17 + 6 * sin((h - 9) / 24 * 2 * .pi) + rng.noise() * 0.1
        let outdoorRH = min(95, max(25, 68 - 22 * sin((h - 9) / 24 * 2 * .pi) + rng.noise()))
        
        portable.append(PortableReading(
            t: t,
            schemaVersion: 1,
            seq: portableSeq,
            bootId: portableBoot,
            qualityFlags: portableFlags,
            pm25: pm25,
            pm10: pm10,
            tempC: round1(outdoorTemp),
            rh: outdoorRH.rounded(),
            session: session(at: t)
        ))

        portableSeq += 1
    }

    // MARK: Shapes

    private func co2Target(at t: Date, hour h: Double) -> Double {
        let base: Double
        switch h {
        case ..<6: base = 1100 + (h / 6) * 350            // door shut, bedroom fills overnight
        case ..<7: base = 1450
        case ..<9: base = 1450 - ((h - 7) / 2) * 930      // door opens, air exchanges
        case ..<18: base = 520 + 40 * sin((h - 9) / 9 * .pi)
        case ..<22: base = 520 + ((h - 18) / 4) * 480     // people home, door half shut
        default: base = 1000 + ((h - 22) / 2) * 100
        }
        // Blend the last two hours before launch toward a full room, so the Now screen has something to say.
        let minutesToDemoEnd = demoEnd.timeIntervalSince(t) / 60
        if minutesToDemoEnd <= 0 {
            return 1180 + 40 * sin(-minutesToDemoEnd / 45 * .pi)
        }
        if minutesToDemoEnd < 120 {
            let k = 1 - minutesToDemoEnd / 120
            return base + (1180 - base) * k
        }
        return base
    }

    private func pmTarget(at t: Date, hour h: Double) -> Double {
        var base = 10 + 3 * sin((h - 4) / 24 * 2 * .pi)
        if smoke.contains(t) {
            let f = t.timeIntervalSince(smoke.lowerBound) / smoke.upperBound.timeIntervalSince(smoke.lowerBound)
            base += 42 * sin(f * .pi)
        }
        if porchRun.contains(t) {
            base += 3
        }
        return base
    }

    private func session(at t: Date) -> PortableSession {
        if porchRun.contains(t) { return .porch }
        let before = porchRun.lowerBound.addingTimeInterval(-5 * 60)..<porchRun.lowerBound
        let after = porchRun.upperBound..<porchRun.upperBound.addingTimeInterval(5 * 60)
        if before.contains(t) || after.contains(t) { return .moving }
        return .window
    }

    private func hourOfDay(_ t: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: t)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    private func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
}
