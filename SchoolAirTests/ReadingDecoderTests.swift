import Testing
import Foundation
@testable import SchoolAir

struct ReadingDecoderTests {
    @Test("An indoor reading decodes from the agreed Firebase shape")
    func indoor() throws {
        let value: [String: Any] = [
            "t": 1_800_000_000_000, "schemaVersion": 1, "seq": 42, "bootId": "boot-a1f3",
            "qualityFlags": ["incomplete"], "co2": 1120, "tempC": 22.6, "rh": 43,
        ]
        let reading = try ReadingDecoder.indoor(from: value)
        #expect(reading.t == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reading.seq == 42)
        #expect(reading.bootId == "boot-a1f3")
        #expect(reading.qualityFlags == [.incomplete])
        #expect(reading.co2 == 1120)
        #expect(reading.rh == 43)
    }

    @Test("Missing keys become nil or defaults, never zero")
    func missingKeys() throws {
        let value: [String: Any] = ["t": 1_800_000_000_000]
        let reading = try ReadingDecoder.indoor(from: value)
        #expect(reading.co2 == nil)
        #expect(reading.tempC == nil)
        #expect(reading.qualityFlags.isEmpty)
        #expect(reading.seq == 0)
    }

    @Test("A portable reading decodes, unknown flags are ignored, and a missing session is unknown")
    func portable() throws {
        let value: [String: Any] = [
            "t": 1_800_000_000_000, "seq": 3, "bootId": "boot-7c02",
            "qualityFlags": ["warming_up", "some_future_flag"],
            "pm25std": 12.4, "pm25env": 11.4, "pm10": 19, "tempC": 18.2, "rh": 61,
        ]
        let reading = try ReadingDecoder.portable(from: value)
        #expect(reading.qualityFlags == [.warmingUp])
        #expect(reading.pm25 == 11.4)
        #expect(reading.session == .unknown)

        var withSession = value
        withSession["session"] = "porch"
        #expect(try ReadingDecoder.portable(from: withSession).session == .porch)
    }

    @Test("Current firmware pm25 wins over legacy fields; CF=1 is never substituted")
    func environmentalPM() throws {
        let current = try ReadingDecoder.portable(from: ["t": 1_792_141_031_226, "pm25": 4, "pm25env": 9, "pm25std": 15])
        #expect(current.pm25 == 4)
        #expect(current.t == Date(timeIntervalSince1970: 1_792_141_031.226))
        #expect(try ReadingDecoder.portable(from: ["t": 1_792_141_031_226, "pm25std": 15]).pm25 == nil)
    }

    @Test("A reading without a timestamp is rejected")
    func noTimestamp() {
        #expect(throws: (any Error).self) {
            try ReadingDecoder.indoor(from: ["co2": 600])
        }
    }

    @Test("Nodes take their id from the key")
    func node() throws {
        let node = try ReadingDecoder.node(id: "home-in", from: ["name": "Indoor box", "kind": "indoor", "location": "Bedroom", "schemaVersion": 1])
        #expect(node.id == "home-in")
        #expect(node.kind == .indoor)
    }

    @Test("History comes back sorted by time whatever order Firebase used")
    func historySorted() {
        let value: [String: Any] = [
            "-Nb2": ["t": 1_800_000_120_000, "co2": 610],
            "-Nb1": ["t": 1_800_000_060_000, "co2": 605],
            "-Nb0": ["t": 1_800_000_000_000, "co2": 600],
            "junk": "not a reading",
        ]
        let history = ReadingDecoder.indoorHistory(from: value)
        #expect(history.map(\.co2) == [600, 605, 610])
    }

    @Test("A recorded session round-trips through the app's JSON coders")
    func recordedSessionRoundTrip() throws {
        let session = RecordedSession(
            title: "Home pilot day 3",
            nodes: PlaceholderWorld.nodes,
            indoor: [IndoorReading(t: Date(timeIntervalSince1970: 1_800_000_000), schemaVersion: 1, seq: 1, bootId: "b", qualityFlags: [], co2: 700, tempC: 22, rh: 40)],
            portable: [],
            events: [EventMarker(kind: .hepaOn, at: Date(timeIntervalSince1970: 1_800_000_000), note: "on")]
        )
        let data = try JSONEncoder.schoolAir.encode(session)
        let back = try JSONDecoder.schoolAir.decode(RecordedSession.self, from: data)
        #expect(back.indoor.first?.co2 == 700)
        #expect(back.events.first?.kind == .hepaOn)
    }
}
