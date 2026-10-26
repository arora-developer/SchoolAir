import Testing
import Foundation
@testable import SchoolAir

struct HistorySeriesTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minute(_ m: Int) -> Date { start.addingTimeInterval(Double(m) * 60) }

    @Test("A missing stretch of minutes becomes a gap and splits the line into two segments")
    func gapSplitsSegments() {
        var samples: [(Date, Double?)] = []
        for m in 0..<10 { samples.append((minute(m), 400)) }
        for m in 20..<30 { samples.append((minute(m), 500)) }

        let series = HistorySeries.build(samples: samples, from: start, to: minute(29), bucket: nil)

        #expect(series.points.count == 20)
        #expect(series.gaps.count == 1)
        #expect(series.gaps.first?.start == minute(9))
        #expect(series.gaps.first?.end == minute(20))
        #expect(Set(series.points.map(\.segment)).count == 2)
    }

    @Test("Readings without a value are never drawn as zero")
    func nilIsNotZero() {
        let samples: [(Date, Double?)] = [(minute(0), 400), (minute(1), nil), (minute(2), nil), (minute(3), 410)]
        let series = HistorySeries.build(samples: samples, from: start, to: minute(3), bucket: nil)
        #expect(series.points.count == 2)
        let drawsZero = series.points.contains { $0.value == 0 }
        #expect(!drawsZero)
        #expect(series.gaps.count == 1, "two missing minutes is a hole longer than the gap threshold")
    }

    @Test("Bucketing averages inside each bucket and leaves empty buckets as gaps")
    func bucketing() {
        var samples: [(Date, Double?)] = []
        for m in 0..<60 { samples.append((minute(m), 10)) }
        for m in 90..<120 { samples.append((minute(m), 20)) }

        let series = HistorySeries.build(samples: samples, from: start, to: minute(119), bucket: 600)

        #expect(series.points.count == 9)
        #expect(series.points.first?.value == 10)
        #expect(series.points.last?.value == 20)
        #expect(series.gaps.count == 1)
    }

    @Test("No samples at all is one gap across the whole window")
    func emptyIsOneGap() {
        let series = HistorySeries.build(samples: [], from: start, to: minute(60), bucket: nil)
        #expect(series.points.isEmpty)
        #expect(series.gaps.count == 1)
        #expect(series.gaps.first?.duration == 3600)
    }

    @Test("A box that went quiet shows a trailing gap up to now")
    func trailingGap() {
        let samples: [(Date, Double?)] = (0..<10).map { (minute($0), 400) }
        let series = HistorySeries.build(samples: samples, from: start, to: minute(60), bucket: nil)
        #expect(series.gaps.count == 1)
        #expect(series.gaps.first?.end == minute(60))
    }

    @Test("Nearest point lookup for scrubbing")
    func nearest() {
        let samples: [(Date, Double?)] = (0..<10).map { (minute($0), Double($0)) }
        let series = HistorySeries.build(samples: samples, from: start, to: minute(9), bucket: nil)
        #expect(series.nearest(to: minute(4).addingTimeInterval(20))?.value == 4)
        #expect(series.nearest(to: minute(4).addingTimeInterval(40))?.value == 5)
    }

    @Test("A short outage inside a large averaging bucket still splits the line")
    func gapInsideBucket() {
        let samples: [(Date, Double?)] = [(minute(0), 10), (minute(1), 10), (minute(5), 20), (minute(6), 20)]
        let series = HistorySeries.build(samples: samples, from: start, to: minute(6), bucket: 1800)
        #expect(series.points.count == 2)
        #expect(series.gaps.count == 1)
        #expect(Set(series.points.map(\.segment)).count == 2)
        #expect(series.points.allSatisfy { $0.t <= minute(6) })
    }
}
