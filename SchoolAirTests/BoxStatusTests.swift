import Testing
import Foundation
@testable import SchoolAir

struct BoxStatusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(age: TimeInterval, flags: [QualityFlag] = []) -> IndoorReading {
        IndoorReading(t: now.addingTimeInterval(-age), schemaVersion: 1, seq: 1, bootId: "b", qualityFlags: flags, co2: 600, tempC: 22, rh: 45)
    }

    @Test func noReadingIsMissing() {
        #expect(BoxStatus.evaluate(nil as IndoorReading?, now: now) == .missing)
    }

    @Test func freshReadingIsLive() {
        #expect(BoxStatus.evaluate(reading(age: 60), now: now) == .live)
    }

    @Test("Three minutes without a reading is stale")
    func staleAfterThreeMinutes() {
        #expect(BoxStatus.evaluate(reading(age: 179), now: now) == .live)
        #expect(BoxStatus.evaluate(reading(age: 181), now: now) == .stale(age: 181))
    }

    @Test("Stale wins over any flag, and sensor-missing wins over warming-up")
    func precedence() {
        #expect(BoxStatus.evaluate(reading(age: 600, flags: [.warmingUp]), now: now) == .stale(age: 600))
        #expect(BoxStatus.evaluate(reading(age: 30, flags: [.warmingUp, .sensorMissing]), now: now) == .sensorMissing)
        #expect(BoxStatus.evaluate(reading(age: 30, flags: [.warmingUp]), now: now) == .warmingUp)
        #expect(BoxStatus.evaluate(reading(age: 30, flags: [.incomplete]), now: now) == .incomplete)
    }

    @Test("Only live and incomplete readings may feed the advice")
    func canAdvise() {
        #expect(BoxStatus.live.canAdvise)
        #expect(BoxStatus.incomplete.canAdvise)
        #expect(!BoxStatus.warmingUp.canAdvise)
        #expect(!BoxStatus.sensorMissing.canAdvise)
        #expect(!BoxStatus.stale(age: 500).canAdvise)
        #expect(!BoxStatus.missing.canAdvise)
    }
}
