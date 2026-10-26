import Foundation

/// A saved session on disk, so the video has something to show if the live air is boring that day.
/// Export one from real data with `JSONEncoder.schoolAir`; the README documents the shape.
struct RecordedSession: Codable, Sendable {
    var title: String
    var nodes: [Node]
    var indoor: [IndoorReading]
    var portable: [PortableReading]
    var events: [EventMarker]
}

/// Replays a `RecordedSession`. Everything it emits is marked `.recorded` and labelled on screen.
final class RecordedReadingSource: ReadingSource {
    let label: String
    private let url: URL
    private let shiftToNow: Bool

    /// - Parameters:
    ///   - url: the JSON file.
    ///   - shiftToNow: slide every timestamp so the last reading lands at launch time. The screen still
    ///     says "recorded"; this only keeps the stale-data logic from hiding the replay.
    init(url: URL, shiftToNow: Bool = true) {
        self.url = url
        self.shiftToNow = shiftToNow
        self.label = "Recorded · \(url.lastPathComponent)"
    }

    func snapshots() -> AsyncStream<AirSnapshot> {
        AsyncStream { [url, shiftToNow] continuation in
            defer { continuation.finish() }
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder.schoolAir.decode(RecordedSession.self, from: data)
            else {
                // Nothing to show beats something made up. The screens show "No data".
                return
            }
            var indoor = session.indoor.sorted { $0.t < $1.t }
            var portable = session.portable.sorted { $0.t < $1.t }
            var events = session.events.map { var e = $0; e.isPlaceholder = true; return e }

            if shiftToNow, let last = max(indoor.last?.t ?? .distantPast, portable.last?.t ?? .distantPast) as Date?, last != .distantPast {
                let offset = Date().timeIntervalSince(last)
                indoor = indoor.map { var r = $0; r.t = r.t.addingTimeInterval(offset); return r }
                portable = portable.map { var r = $0; r.t = r.t.addingTimeInterval(offset); return r }
                events = events.map { var e = $0; e.at = e.at.addingTimeInterval(offset); return e }
            }

            continuation.yield(AirSnapshot(
                nodes: session.nodes,
                latestIndoor: indoor.last,
                latestPortable: portable.last,
                indoorHistory: indoor,
                portableHistory: portable,
                placeholderEvents: events,
                provenance: .recorded,
                receivedAt: Date()
            ))
        }
    }
}
