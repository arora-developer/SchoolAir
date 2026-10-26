import Foundation

/// Turns a list of readings into something a chart can draw, without hiding gaps.
///
/// A missing minute is a gap. It is never filled with a zero or interpolated across.
struct HistorySeries: Hashable, Sendable {
    struct Point: Identifiable, Hashable, Sendable {
        var t: Date
        var value: Double
        /// Points in the same segment are joined by a line. A new segment starts after every gap.
        var segment: Int
        var id: Date { t }
    }

    struct Gap: Identifiable, Hashable, Sendable {
        var start: Date
        var end: Date
        var id: Date { start }
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    var points: [Point]
    var gaps: [Gap]

    static let empty = HistorySeries(points: [], gaps: [])

    /// - Parameters:
    ///   - samples: (time, value) pairs in time order. A `nil` value is a reading that carried no number.
    ///   - start, end: the window to draw.
    ///   - bucket: averaging window in seconds. `nil` keeps every sample.
    ///   - expectedInterval: how often the box should post. A hole longer than `gapFactor` × interval is a gap.
    static func build(
        samples: [(Date, Double?)],
        from start: Date,
        to end: Date,
        bucket: TimeInterval?,
        expectedInterval: TimeInterval = 60,
        gapFactor: Double = 2.5
    ) -> HistorySeries {
        let raw = samples.filter { $0.0 >= start && $0.0 <= end }
            .compactMap { t, value in value.flatMap { $0.isFinite ? (t, $0) : nil } }
        guard !raw.isEmpty else { return HistorySeries(points: [], gaps: [Gap(start: start, end: end)]) }
        let threshold = expectedInterval * gapFactor
        var gaps: [Gap] = []
        var segments: [[(Date, Double)]] = [[]]
        var previous = start
        for (time, value) in raw {
            if time.timeIntervalSince(previous) > threshold {
                gaps.append(Gap(start: previous, end: time))
                if !segments[segments.count - 1].isEmpty { segments.append([]) }
            }
            segments[segments.count - 1].append((time, value))
            previous = time
        }
        if end.timeIntervalSince(previous) > threshold { gaps.append(Gap(start: previous, end: end)) }
        var points: [Point] = []
        for (segment, values) in segments.enumerated() {
            if let bucket, bucket > 0 {
                var buckets: [Int: (sum: Double, count: Int, time: Double)] = [:]
                for (time, value) in values {
                    let index = Int(time.timeIntervalSince(start) / bucket)
                    let current = buckets[index, default: (0, 0, 0)]
                    buckets[index] = (current.sum + value, current.count + 1, current.time + time.timeIntervalSince(start))
                }
                for index in buckets.keys.sorted() {
                    let entry = buckets[index]!
                    // Average actual sample times: never put a point outside its data or beyond now.
                    points.append(Point(t: start.addingTimeInterval(entry.time / Double(entry.count)),
                                        value: entry.sum / Double(entry.count), segment: segment))
                }
            } else {
                points += values.map { Point(t: $0.0, value: $0.1, segment: segment) }
            }
        }
        return HistorySeries(points: points, gaps: gaps)
    }

    /// The point nearest a time, for chart scrubbing.
    func nearest(to date: Date) -> Point? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].t < date { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return points[0] }
        if low == points.count { return points[low - 1] }
        return date.timeIntervalSince(points[low - 1].t) <= points[low].t.timeIntervalSince(date)
            ? points[low - 1] : points[low]
    }
}
