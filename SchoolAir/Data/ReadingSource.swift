import Foundation

/// Everything the app knows about the boxes at one moment.
struct AirSnapshot: Sendable {
    /// Where the numbers came from. Anything but `.live` is labelled on screen, every time it appears.
    enum Provenance: String, Sendable {
        case live
        case recorded
        case placeholder
    }

    var nodes: [Node]
    var latestIndoor: IndoorReading?
    var latestPortable: PortableReading?
    /// Ascending by time. Up to seven days.
    var indoorHistory: [IndoorReading]
    var portableHistory: [PortableReading]
    /// Event markers that came with placeholder or recorded data. Never persisted.
    var placeholderEvents: [EventMarker]
    var provenance: Provenance
    var receivedAt: Date
    var connected: Bool? = nil
    var issues: [String: String] = [:]

    var indoorNode: Node? { nodes.first { $0.kind == .indoor } }
    var portableNode: Node? { nodes.first { $0.kind == .portable } }
}

/// Where readings come from. Swap the implementation, keep the screens.
///
/// - `PlaceholderReadingSource`: made-up numbers while the boxes are being built.
/// - `RecordedReadingSource`: a labelled replay of a saved session, for the video.
/// - `FirebaseReadingSource`: the real thing, once the Firebase SDK is added.
protocol ReadingSource: AnyObject {
    var label: String { get }
    func snapshots() -> AsyncStream<AirSnapshot>
}
