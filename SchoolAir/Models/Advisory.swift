import Foundation

/// The four situations version one knows about, plus the honest fallback.
enum Situation: String, Hashable, Sendable, CaseIterable {
    /// CO2 below the ventilation prompt and outdoor particles below the advisory level.
    case belowPrompts
    /// CO2 elevated, outdoor air fine: the room needs more outside air.
    case needsOutsideAir
    /// CO2 elevated and outdoor particles elevated: more outside air brings particles in.
    case conflict
    /// Outdoor particles elevated, CO2 normal: keep outside air out, rely on filtration.
    case outdoorAdvisory
    /// Readings stale, missing, or from an unknown location. Never a green light.
    case insufficient

    var title: String {
        switch self {
        case .belowPrompts: "No prompt"
        case .needsOutsideAir: "Ventilation prompt"
        case .conflict: "Conflict"
        case .outdoorAdvisory: "Outdoor advisory"
        case .insufficient: "Insufficient information"
        }
    }

    var symbol: String {
        switch self {
        case .belowPrompts: "checkmark.circle"
        case .needsOutsideAir: "wind"
        case .conflict: "exclamationmark.triangle"
        case .outdoorAdvisory: "aqi.medium"
        case .insufficient: "questionmark.circle"
        }
    }
}

/// What the Now screen says at the top.
struct Advisory: Hashable, Sendable {
    var situation: Situation
    var headline: String
    var body: String
    /// Concrete things the adult in charge can do. Empty when there is nothing to do or nothing to say.
    var prompts: [String]
    /// For `.insufficient`: what exactly is missing, so nobody has to guess.
    var reasons: [String]
    var tone: Tone
}

/// Weighs indoor CO2 against outdoor particles. The one piece of judgment in version one.
///
/// Uses separate trigger and clear thresholds so the advice does not chatter when a number
/// sits on a line. Once CO2 is "elevated" it stays elevated until it drops below the clear level.
struct AdvisoryEngine: Hashable, Sendable {
    struct Thresholds: Hashable, Sendable {
        /// CO2 becomes elevated at or above this, in ppm.
        var co2Trigger: Double = 1000
        /// ...and clears only when it falls below this.
        var co2Clear: Double = 900
        /// Outdoor PM2.5 becomes elevated at or above this, in µg/m³ (EPA "unhealthy for sensitive groups").
        var pm25Trigger: Double = 35.5
        /// ...and clears only when it falls below this.
        var pm25Clear: Double = 30.0

        static let v1 = Thresholds()
    }

    struct Input: Hashable, Sendable {
        var co2: Double?
        var co2Status: BoxStatus
        var outdoorPM25: Double?
        var outdoorStatus: BoxStatus
        var outdoorSession: PortableSession
        /// People in the room, if someone typed it in. Used in the wording, not in the thresholds.
        var occupancy: Int?
    }

    var thresholds: Thresholds
    private(set) var co2Elevated = false
    private(set) var pmElevated = false

    init(thresholds: Thresholds = .v1) {
        self.thresholds = thresholds
    }

    /// Evaluate the latest inputs. Mutates the hysteresis state, so keep one engine per room.
    mutating func evaluate(_ input: Input) -> Advisory {
        var reasons: [String] = []

        if !input.co2Status.canAdvise {
            reasons.append("Indoor box: \(input.co2Status.label.lowercased())")
        } else if input.co2 == nil {
            reasons.append("Indoor box: latest reading has no CO2 value")
        }

        if !input.outdoorStatus.canAdvise {
            reasons.append("Portable box: \(input.outdoorStatus.label.lowercased())")
        } else if input.outdoorPM25 == nil {
            reasons.append("Portable box: latest reading has no PM2.5 value")
        } else if !input.outdoorSession.isKnownLocation {
            reasons.append("Portable box: location unknown")
        }

        guard reasons.isEmpty, let co2 = input.co2, let pm = input.outdoorPM25 else {
            // Deliberately leaves co2Elevated / pmElevated alone: a dropout should not reset the room's state.
            return Advisory(
                situation: .insufficient,
                headline: "Insufficient current information.",
                body: "School Air will not guess. It needs a fresh reading from both boxes and a known location for the portable box.",
                prompts: [],
                reasons: reasons,
                tone: .gray
            )
        }

        co2Elevated = co2Elevated ? (co2 >= thresholds.co2Clear) : (co2 >= thresholds.co2Trigger)
        pmElevated = pmElevated ? (pm >= thresholds.pm25Clear) : (pm >= thresholds.pm25Trigger)

        let people = input.occupancy.map { "\($0) people" } ?? "this many people"

        switch (co2Elevated, pmElevated) {
        case (true, false):
            return Advisory(
                situation: .needsOutsideAir,
                headline: "The room needs more outside air for \(people).",
                body: "CO2 is elevated for the number of people in the room, and the outside air is fine to bring in.",
                prompts: [
                    "Raise the HVAC outdoor-air setting.",
                    "Open windows where the building allows.",
                ],
                reasons: [],
                tone: .orange
            )
        case (true, true):
            return Advisory(
                situation: .conflict,
                headline: "More outside air would bring particles in.",
                body: "CO2 is elevated for \(people) and outdoor particles are elevated at the same time. The usual fix, more outside air, pulls particles in. Facilities decides.",
                prompts: [
                    "Filtration first: a portable HEPA unit or the building's filters.",
                    "Keep windows shut.",
                    "Fewer people in the room, or move the group.",
                ],
                reasons: [],
                tone: .red
            )
        case (false, true):
            return Advisory(
                situation: .outdoorAdvisory,
                headline: "Outdoor particles are elevated.",
                body: "CO2 is below the ventilation prompt. Keep outside air out while particles are high. This does not mean the room is safe.",
                prompts: [
                    "Keep windows shut.",
                    "Rely on filtration.",
                ],
                reasons: [],
                tone: .yellow
            )
        case (false, false):
            return Advisory(
                situation: .belowPrompts,
                headline: "No prompt right now.",
                body: "CO2 is below the ventilation prompt and outdoor particles are below the advisory level. These are product thresholds we chose, not health limits.",
                prompts: [],
                reasons: [],
                tone: .green
            )
        }
    }

    mutating func reset() {
        co2Elevated = false
        pmElevated = false
    }
}
