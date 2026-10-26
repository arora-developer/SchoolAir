import Testing
import Foundation
@testable import SchoolAir

struct PlaceholderWorldTests {
    @Test("The placeholder week has the shapes the screens need to show")
    func shapes() {
        let now = Date()
        let world = PlaceholderWorld(now: now)

        #expect(world.indoor.count > 9_000, "about a week of minute readings")
        #expect(world.portable.count > 9_000)

        // Latest reading is at the current minute, so the boxes read as live.
        #expect(now.timeIntervalSince(world.indoor.last!.t) < 61)

        // Missing numbers are nil, never zero.
        let hasZeroCO2 = world.indoor.contains { $0.co2 == 0 }
        let hasWarmUpWithNil = world.indoor.contains { $0.qualityFlags.contains(.warmingUp) && $0.co2 == nil }
        #expect(!hasZeroCO2)
        #expect(hasWarmUpWithNil)

        // One reboot on the indoor box: two boot ids, and seq restarts.
        #expect(Set(world.indoor.map(\.bootId)).count == 2)

        // The Wi-Fi outage is a hole of about 40 minutes, not a run of zeros.
        let biggestHole = zip(world.indoor, world.indoor.dropFirst())
            .map { $1.t.timeIntervalSince($0.t) }
            .max() ?? 0
        #expect(biggestHole > 35 * 60 && biggestHole < 45 * 60)

        // The portable box went to the porch at some point.
        let wentToPorch = world.portable.contains { $0.session == .porch }
        let wasMoving = world.portable.contains { $0.session == .moving }
        #expect(wentToPorch)
        #expect(wasMoving)

        // Placeholder events are marked so they are never saved.
        let allMarked = world.events.allSatisfy(\.isPlaceholder)
        #expect(allMarked)
    }

    @Test("Advancing appends one reading per minute")
    func advancing() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var world = PlaceholderWorld(now: start, days: 1)
        let before = world.indoor.count
        world.advance(to: start.addingTimeInterval(5 * 60))
        #expect(world.indoor.count == before + 5)
        #expect(world.snapshot().provenance == .placeholder)
    }

    @Test("The seeded generator is deterministic")
    func determinism() {
        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        let fromA = (0..<10).map { _ in a.next() }
        let fromB = (0..<10).map { _ in b.next() }
        #expect(fromA == fromB)
    }
}
