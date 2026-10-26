import Foundation

/// The official regional air report from AirNow. Context, not ground truth.
///
/// This is an index (AQI), not a concentration, and it comes from an EPA monitor across town.
/// It gets its own card with its own label and time and is never plotted on the same axis as our µg/m³.
struct RegionalAQI: Hashable, Sendable {
    var aqi: Int
    var categoryNumber: Int
    var categoryName: String
    /// The pollutant the AQI was computed from, e.g. "PM2.5" or "O3".
    var parameter: String
    var reportingArea: String
    var stateCode: String
    var observed: Date
    var isPlaceholder: Bool
    var isModeled: Bool = false
    var sourceLabel: String = "AirNow"
    var pm25: Double? = nil

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(observed) > 3 * 3600 }

    var tone: Tone { AQIBands.tone(forCategory: categoryNumber) }
}
