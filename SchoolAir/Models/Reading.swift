import Foundation

/// Flags the box firmware writes next to a reading.
/// A value that could not be measured is `nil` in the app and absent in Firebase. Never zero.
enum QualityFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case warmingUp = "warming_up"
    case sensorMissing = "sensor_missing"
    case incomplete

    var label: String {
        switch self {
        case .warmingUp: "Warming up"
        case .sensorMissing: "Sensor missing"
        case .incomplete: "Incomplete"
        }
    }
}

/// Where the portable box was when it measured. Logged each time the box moves.
enum PortableSession: String, Codable, CaseIterable, Hashable, Sendable {
    case window
    case porch
    case moving
    case unknown

    var label: String {
        switch self {
        case .window: "By the window"
        case .porch: "On the porch"
        case .moving: "Moving"
        case .unknown: "Unknown location"
        }
    }

    /// The advisory logic only trusts outdoor particles from a known place.
    var isKnownLocation: Bool { self != .unknown }
}

/// Fields every reading carries, whichever box wrote it.
///
/// `t` is stamped by Firebase (`{".sv": "timestamp"}`); the board has no clock.
/// `seq` counts up from boot and `bootId` changes on every restart, so gaps and restarts show in the data.
protocol AirReading: Identifiable, Hashable, Sendable {
    var t: Date { get }
    var schemaVersion: Int { get }
    var seq: Int { get }
    var bootId: String { get }
    var qualityFlags: [QualityFlag] { get }
}

extension AirReading {
    var id: String { "\(bootId)#\(seq)" }
}

/// One reading from the indoor box (SCD-41). Mirrors `/readings/{id}/{autoId}` and `/latest/{id}`.
struct IndoorReading: AirReading, Codable {
    var t: Date
    var schemaVersion: Int
    var seq: Int
    var bootId: String
    var qualityFlags: [QualityFlag]
    var co2: Double?
    var tempC: Double?
    var rh: Double?
}

/// One reading from the portable box (PMSA003I + SHT45).
struct PortableReading: AirReading, Codable {
    var t: Date
    var schemaVersion: Int
    var seq: Int
    var bootId: String
    var qualityFlags: [QualityFlag]
    var pm25: Double?
    var pm10: Double?
    var tempC: Double?
    var rh: Double?
    var session: PortableSession

}

// MARK: - Lenient decoding

// Firebase drops empty arrays and older firmware may not write every key,
// so decoding fills sensible defaults instead of failing.

extension IndoorReading {
    private enum CodingKeys: String, CodingKey {
        case t, schemaVersion, seq, bootId, qualityFlags, co2, tempC, rh
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Date.self, forKey: .t)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        bootId = try c.decodeIfPresent(String.self, forKey: .bootId) ?? "unknown"
        qualityFlags = QualityFlag.decodeLeniently(from: c, forKey: .qualityFlags)
        co2 = try c.decodeIfPresent(Double.self, forKey: .co2)
        tempC = try c.decodeIfPresent(Double.self, forKey: .tempC)
        rh = try c.decodeIfPresent(Double.self, forKey: .rh)
    }
}


extension PortableReading {
    private enum CodingKeys: String, CodingKey {
        case t, schemaVersion, seq, bootId, qualityFlags
        case pm25, pm25env, pm10, tempC, rh, session
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        t = try c.decode(Date.self, forKey: .t)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        bootId = try c.decodeIfPresent(String.self, forKey: .bootId) ?? "unknown"

        qualityFlags = QualityFlag.decodeLeniently(
            from: c,
            forKey: .qualityFlags
        )

        pm25 = try c.decodeIfPresent(Double.self, forKey: .pm25) ?? c.decodeIfPresent(Double.self, forKey: .pm25env)
        pm10 = try c.decodeIfPresent(Double.self, forKey: .pm10)
        tempC = try c.decodeIfPresent(Double.self, forKey: .tempC)
        rh = try c.decodeIfPresent(Double.self, forKey: .rh)

        let rawSession = try c.decodeIfPresent(
            String.self,
            forKey: .session
        )
        session = rawSession.flatMap(PortableSession.init(rawValue:)) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(t, forKey: .t)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(seq, forKey: .seq)
        try c.encode(bootId, forKey: .bootId)
        try c.encode(qualityFlags, forKey: .qualityFlags)
        try c.encodeIfPresent(pm25, forKey: .pm25)
        try c.encodeIfPresent(pm10, forKey: .pm10)
        try c.encodeIfPresent(tempC, forKey: .tempC)
        try c.encodeIfPresent(rh, forKey: .rh)
        try c.encode(session.rawValue, forKey: .session)
    }
}

extension QualityFlag {
    /// Unknown flag strings from newer firmware are ignored rather than failing the whole reading.
    static func decodeLeniently<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) -> [QualityFlag] {
        let raw = (try? container.decodeIfPresent([String].self, forKey: key)) ?? []
        return raw.compactMap(QualityFlag.init(rawValue:))
    }
}

// MARK: - JSON coders with the contract's date format

extension JSONDecoder {
    /// `t` is milliseconds since 1970, the way Firebase stamps it.
    static var schoolAir: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}

extension JSONEncoder {
    static var schoolAir: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
