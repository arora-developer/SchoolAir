import Foundation

enum Measure {
    /// "0 min", "45 min", "2 h", "2 h 10 min".
    static func minutesText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    /// "22.6 °C", "46%", or "No data". Never a zero standing in for a missing number.
    static func text(_ value: Double?, unit: String, digits: Int) -> String {
        guard let value else { return "No data" }
        return unit == "%" ? "\(value.text(digits))%" : "\(value.text(digits)) \(unit)"
    }

    /// The footnote under a box reading.
    static func footnote(value: Double?, measuredAt: Date?, flags: [QualityFlag]) -> String {
        if value == nil {
            let why = flags.map(\.label).joined(separator: ", ")
            return why.isEmpty ? "No reading. Nothing is filled in." : "No reading: \(why.lowercased())."
        }
        let when = measuredAt.map { $0.dayClockText } ?? "time unknown"
        return "Sensor reading · \(when)"
    }
}

extension Date {
    /// "2:14 PM"
    var clockText: String { formatted(date: .omitted, time: .shortened) }
    /// "Tue 2:14 PM"
    var dayClockText: String { formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
}

extension Double {
    /// Locale-aware number with a fixed number of decimals: 1,120 or 12.4.
    func text(_ digits: Int) -> String {
        formatted(.number.precision(.fractionLength(digits)))
    }
}
