import Foundation

/// Numbers that summarize a stretch of readings. Pure functions, so they are unit tested.
///
/// Every reading stands for one minute, because the boxes post once a minute. A missing
/// minute is simply not counted; it is never treated as a zero.
enum Insights {
    struct Summary: Hashable, Sendable {
        /// Minutes with CO2 at or above the ventilation prompt.
        var minutesAbovePrompt: Int
        var peakCO2: Double?
        var peakCO2At: Date?
        var averagePM25: Double?
        var peakPM25: Double?
        /// Minutes with outdoor PM2.5 at or above the advisory level.
        var minutesAboveAdvisory: Int
    }

    /// How well a box kept up. The plan's target is 95% of expected minute records.
    struct BoxHealth: Hashable, Sendable {
        var received: Int
        var expected: Int
        /// Distinct boot ids seen, minus one.
        var restarts: Int
        /// The longest silence, if it was long enough to count as a gap.
        var longestGap: TimeInterval?

        var share: Double {
            expected > 0 ? min(1, Double(received) / Double(expected)) : 0
        }
    }

    struct Stats: Hashable, Sendable {
        var min: Double
        var average: Double
        var max: Double
    }

    static func summary(
        indoor: [IndoorReading],
        portable: [PortableReading],
        from start: Date,
        to end: Date,
        co2Trigger: Double,
        pm25Trigger: Double
    ) -> Summary {
        var aboveMinutes = Set<Int>()
        var peak: (value: Double, at: Date)?
        for reading in indoor where reading.t >= start && reading.t <= end {
            guard let co2 = reading.co2 else { continue }
            if co2 >= co2Trigger { aboveMinutes.insert(Int(reading.t.timeIntervalSince1970 / 60)) }
            if peak == nil || co2 > peak!.value { peak = (co2, reading.t) }
        }

        let pmValues = portable
            .filter { $0.t >= start && $0.t <= end }
            .compactMap(\.pm25)

        return Summary(
            minutesAbovePrompt: aboveMinutes.count,
            peakCO2: peak?.value,
            peakCO2At: peak?.at,
            averagePM25: pmValues.isEmpty ? nil : pmValues.reduce(0, +) / Double(pmValues.count),
            peakPM25: pmValues.max(),
            minutesAboveAdvisory: Set(portable.filter { $0.t >= start && $0.t <= end && ($0.pm25 ?? -1) >= pm25Trigger }.map { Int($0.t.timeIntervalSince1970 / 60) }).count
        )
    }

    static func health<R: AirReading>(
        _ readings: [R],
        from start: Date,
        to end: Date,
        expectedInterval: TimeInterval = 60,
        gapFactor: Double = 2.5
    ) -> BoxHealth {
        let inWindow = readings.filter { $0.t >= start && $0.t <= end }
        let expected = Int((end.timeIntervalSince(start) / expectedInterval).rounded(.down))
        let boots = Set(inWindow.map(\.bootId)).count

        var longest: TimeInterval = 0
        if inWindow.isEmpty {
            longest = end.timeIntervalSince(start)
        } else {
            for (a, b) in zip(inWindow, inWindow.dropFirst()) {
                longest = max(longest, b.t.timeIntervalSince(a.t))
            }
            if let last = inWindow.last {
                // A box that went quiet: the silence up to now is a gap too.
                longest = max(longest, end.timeIntervalSince(last.t))
            }
        }

        return BoxHealth(
            received: min(expected, Set(inWindow.map { Int($0.t.timeIntervalSince(start) / expectedInterval) }).count),
            expected: expected,
            restarts: max(0, boots - 1),
            longestGap: longest > expectedInterval * gapFactor ? longest : nil
        )
    }

    static func stats(_ values: [Double]) -> Stats? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return Stats(min: low, average: values.reduce(0, +) / Double(values.count), max: high)
    }
}
