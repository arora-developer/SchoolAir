import Foundation

/// What the app can honestly say about a box right now. Derived from the latest reading, never stored.
enum BoxStatus: Hashable, Sendable {
    case live
    case warmingUp
    case incomplete
    case sensorMissing
    case stale(age: TimeInterval)
    case missing

    /// A box posts once a minute. After this long without a reading we call it stale.
    static let staleAfter: TimeInterval = 3 * 60

    static func evaluate<R: AirReading>(_ reading: R?, now: Date, staleAfter: TimeInterval = BoxStatus.staleAfter) -> BoxStatus {
        guard let reading else { return .missing }
        let age = now.timeIntervalSince(reading.t)
        if age > staleAfter { return .stale(age: age) }
        if reading.qualityFlags.contains(.sensorMissing) { return .sensorMissing }
        if reading.qualityFlags.contains(.warmingUp) { return .warmingUp }
        if reading.qualityFlags.contains(.incomplete) { return .incomplete }
        return .live
    }

    /// Whether a value carried by this reading may feed the advisory logic.
    /// An incomplete reading may still carry the one number we need; the engine checks for `nil` separately.
    var canAdvise: Bool {
        switch self {
        case .live, .incomplete: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .live: "Live"
        case .warmingUp: "Warming up"
        case .incomplete: "Incomplete"
        case .sensorMissing: "Sensor missing"
        case .stale(let age): "Stale · \(BoxStatus.ageText(age))"
        case .missing: "No data"
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .warmingUp: "thermometer.medium"
        case .incomplete: "circle.lefthalf.filled"
        case .sensorMissing: "sensor.tag.radiowaves.forward.fill"
        case .stale: "clock.badge.exclamationmark"
        case .missing: "wifi.slash"
        }
    }

    var tone: Tone {
        switch self {
        case .live: .green
        case .warmingUp, .incomplete: .yellow
        case .stale: .orange
        case .sensorMissing: .red
        case .missing: .gray
        }
    }

    static func ageText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86_400 { return "\(s / 3600) h" }
        return "\(s / 86_400) d"
    }
}
