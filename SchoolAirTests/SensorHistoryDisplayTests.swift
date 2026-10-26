import XCTest
@testable import SchoolAir

final class SensorHistoryDisplayTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func indoor(_ offset: Double, _ value: Double?) -> IndoorReading {
        IndoorReading(t: start.addingTimeInterval(offset), schemaVersion: 1, seq: Int(offset), bootId: "test", qualityFlags: [], co2: value, tempC: 22, rh: 50)
    }
    func portable(_ offset: Double, _ value: Double?) -> PortableReading {
        PortableReading(t: start.addingTimeInterval(offset), schemaVersion: 1, seq: Int(offset), bootId: "test", qualityFlags: [], pm25: value, pm10: 20, tempC: 22, rh: 50, session: .unknown)
    }
    func snapshot(indoor: [IndoorReading] = [], portable: [PortableReading] = []) -> AirSnapshot {
        AirSnapshot(nodes: [], latestIndoor: indoor.last, latestPortable: portable.last,
                    indoorHistory: indoor, portableHistory: portable, placeholderEvents: [], provenance: .live, receivedAt: start)
    }
    func testEachDetailMatchesItsHistoryTabChartAndRawStatistics() {
        let data = snapshot(indoor: [indoor(0, 400), indoor(60, 600), indoor(300, 1000)],
                            portable: [portable(0, 5), portable(60, 15), portable(300, 30)])
        let end = start.addingTimeInterval(600)
        let both = HistoryDisplay.build(snapshot: data, start: start, end: end, bucket: 300, co2Trigger: 1000, pmTrigger: 35)
        for sensor in [NodeKind.indoor, .portable] {
            let one = SensorHistoryDisplay.build(snapshot: data, sensor: sensor, start: start, end: end, bucket: 300)
            XCTAssertEqual(one.series, sensor == .indoor ? both.co2 : both.pm25)
            XCTAssertEqual(one.stats?.average, sensor == .indoor ? both.co2Stats?.average : both.pmStats?.average)
            XCTAssertEqual(one.stats?.max, sensor == .indoor ? 1000 : 30)
        }
    }
    func testMissingSelectedSensorDoesNotUseOtherBoxOrLatestReadingAsHistory() {
        var data = snapshot(portable: [portable(0, 12)])
        data.latestIndoor = indoor(0, 700)
        let one = SensorHistoryDisplay.build(snapshot: data, sensor: .indoor, start: start, end: start.addingTimeInterval(600), bucket: 300)
        XCTAssertTrue(one.series.points.isEmpty)
        XCTAssertNil(one.stats)
        XCTAssertEqual(one.series.gaps.count, 1)
    }
    func testRangeAndMissingValuesDoNotDistortStatistics() {
        let data = snapshot(indoor: [indoor(-1, 5000), indoor(0, nil), indoor(10, .nan), indoor(60, 600), indoor(120, 800), indoor(601, 9000)])
        let one = SensorHistoryDisplay.build(snapshot: data, sensor: .indoor, start: start, end: start.addingTimeInterval(600), bucket: 300)
        XCTAssertEqual(one.stats?.min, 600)
        XCTAssertEqual(one.stats?.max, 800)
        XCTAssertEqual(one.stats?.average, 700)
        XCTAssertEqual(one.series.points.map(\.value), [700])
    }
    func testFullWeekRemainsAveragedInsteadOfRenderingEveryUpload() {
        let readings = (0..<120_960).map { indoor(Double($0 * 5), 700) }
        let one = SensorHistoryDisplay.build(snapshot: snapshot(indoor: readings), sensor: .indoor, start: start, end: start.addingTimeInterval(7 * 86_400), bucket: 1800)
        XCTAssertEqual(one.series.points.count, 336)
        XCTAssertTrue(one.series.gaps.isEmpty)
        XCTAssertEqual(one.stats?.average, 700)
    }
    func testEventMarkersOnlyIncludeSelectedSensorAndSharedRoomEvents() {
        let room = EventMarker(kind: .windowOpened, at: start)
        let inside = EventMarker(kind: .hepaOn, at: start, nodeId: Node.indoorID)
        let outside = EventMarker(kind: .boxMoved, at: start, nodeId: Node.portableID)
        let legacy = EventMarker(kind: .boxMoved, at: start, nodeId: "home-portable")
        let old = EventMarker(kind: .other, at: start.addingTimeInterval(-1))
        let all = [room, inside, outside, legacy, old]
        let window = start...start.addingTimeInterval(600)
        XCTAssertEqual(SensorHistoryDisplay.events(all, for: .indoor, in: window), [room, inside])
        XCTAssertEqual(SensorHistoryDisplay.events(all, for: .portable, in: window), [room, outside, legacy])
    }
}
