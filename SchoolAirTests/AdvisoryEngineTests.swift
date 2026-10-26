import Testing
import Foundation
@testable import SchoolAir

struct AdvisoryEngineTests {
    private func input(
        co2: Double?,
        pm: Double?,
        co2Status: BoxStatus = .live,
        pmStatus: BoxStatus = .live,
        session: PortableSession = .window,
        occupancy: Int? = nil
    ) -> AdvisoryEngine.Input {
        AdvisoryEngine.Input(
            co2: co2, co2Status: co2Status,
            outdoorPM25: pm, outdoorStatus: pmStatus,
            outdoorSession: session, occupancy: occupancy
        )
    }

    @Test("Elevated CO2 with clean outdoor air asks for more outside air")
    func needsOutsideAir() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 1240, pm: 8))
        #expect(advisory.situation == .needsOutsideAir)
        let mentionsOutdoorAir = advisory.prompts.contains { $0.localizedCaseInsensitiveContains("outdoor-air") }
        #expect(mentionsOutdoorAir)
    }

    @Test("Elevated CO2 and elevated outdoor particles is named as a conflict, filtration first")
    func conflict() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 1240, pm: 48))
        #expect(advisory.situation == .conflict)
        #expect(advisory.prompts.first?.localizedCaseInsensitiveContains("filtration") == true)
        let saysWindowsShut = advisory.prompts.contains { $0.localizedCaseInsensitiveContains("windows shut") }
        #expect(saysWindowsShut)
    }

    @Test("Elevated particles with normal CO2 gives the outdoor advisory and never calls the room safe")
    func outdoorAdvisory() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 600, pm: 48))
        #expect(advisory.situation == .outdoorAdvisory)
        #expect(!advisory.headline.localizedCaseInsensitiveContains("safe"))
    }

    @Test("Both below the prompts gives no prompt and no to-do list")
    func belowPrompts() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 600, pm: 8))
        #expect(advisory.situation == .belowPrompts)
        #expect(advisory.prompts.isEmpty)
    }

    @Test("A stale indoor box means insufficient information, with the reason named")
    func staleIsInsufficient() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 1240, pm: 8, co2Status: .stale(age: 600)))
        #expect(advisory.situation == .insufficient)
        #expect(advisory.reasons.count == 1)
        #expect(advisory.reasons.first?.hasPrefix("Indoor box") == true)
    }

    @Test("A missing portable box means insufficient information")
    func missingIsInsufficient() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 600, pm: nil, pmStatus: .missing))
        #expect(advisory.situation == .insufficient)
        #expect(advisory.reasons.first?.hasPrefix("Portable box") == true)
    }

    @Test("An unknown portable location means insufficient information even with fresh numbers")
    func unknownLocationIsInsufficient() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: 600, pm: 8, session: .unknown))
        #expect(advisory.situation == .insufficient)
        let namesLocation = advisory.reasons.contains { $0.localizedCaseInsensitiveContains("location unknown") }
        #expect(namesLocation)
    }

    @Test("A live reading with no number in it is still insufficient")
    func missingValueIsInsufficient() {
        var engine = AdvisoryEngine()
        #expect(engine.evaluate(input(co2: nil, pm: 8)).situation == .insufficient)
    }

    @Test("Insufficient information is never green")
    func insufficientIsNeverGreen() {
        var engine = AdvisoryEngine()
        let advisory = engine.evaluate(input(co2: nil, pm: nil, co2Status: .missing, pmStatus: .missing, session: .unknown))
        #expect(advisory.tone == .gray)
        #expect(advisory.reasons.count == 2)
    }

    @Test("Hysteresis: the prompt holds until CO2 falls below the clear level")
    func hysteresis() {
        var engine = AdvisoryEngine()
        #expect(engine.evaluate(input(co2: 999, pm: 8)).situation == .belowPrompts)
        #expect(engine.evaluate(input(co2: 1000, pm: 8)).situation == .needsOutsideAir)
        #expect(engine.evaluate(input(co2: 950, pm: 8)).situation == .needsOutsideAir, "above the clear level, still elevated")
        #expect(engine.evaluate(input(co2: 899, pm: 8)).situation == .belowPrompts, "below the clear level")
        #expect(engine.evaluate(input(co2: 999, pm: 8)).situation == .belowPrompts, "not re-triggered until the trigger level")
    }

    @Test("Hysteresis works the same way for outdoor particles")
    func particleHysteresis() {
        var engine = AdvisoryEngine()
        #expect(engine.evaluate(input(co2: 600, pm: 35.4)).situation == .belowPrompts)
        #expect(engine.evaluate(input(co2: 600, pm: 35.5)).situation == .outdoorAdvisory)
        #expect(engine.evaluate(input(co2: 600, pm: 31)).situation == .outdoorAdvisory)
        #expect(engine.evaluate(input(co2: 600, pm: 29.9)).situation == .belowPrompts)
    }

    @Test("A dropout does not reset the room's state")
    func dropoutKeepsState() {
        var engine = AdvisoryEngine()
        _ = engine.evaluate(input(co2: 1200, pm: 8))
        #expect(engine.evaluate(input(co2: nil, pm: 8, co2Status: .stale(age: 400))).situation == .insufficient)
        #expect(engine.evaluate(input(co2: 950, pm: 8)).situation == .needsOutsideAir)
    }

    @Test("Occupancy shows up in the wording only")
    func occupancyWording() {
        var engine = AdvisoryEngine()
        let with = engine.evaluate(input(co2: 1200, pm: 8, occupancy: 24))
        #expect(with.headline.contains("24 people"))
        var without = AdvisoryEngine()
        let plain = without.evaluate(input(co2: 1200, pm: 8))
        #expect(plain.situation == with.situation)
    }
}
