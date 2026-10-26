import Foundation

/// Something a person did that might explain a change in the chart. Added by hand.
enum EventKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case hvacChanged = "hvac_changed"
    case windowOpened = "window_opened"
    case hepaOn = "hepa_on"
    case classEnded = "class_ended"
    case boxMoved = "box_moved"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hvacChanged: "HVAC setting changed"
        case .windowOpened: "Window opened"
        case .hepaOn: "HEPA turned on"
        case .classEnded: "Class ended"
        case .boxMoved: "Box moved"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .hvacChanged: "fan"
        case .windowOpened: "window.casement"
        case .hepaOn: "air.purifier"
        case .classEnded: "person.2.slash"
        case .boxMoved: "shippingbox"
        case .other: "pin"
        }
    }
}

struct EventMarker: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: EventKind
    var at: Date
    /// Which box it concerns. `nil` means the room, or both boxes.
    var nodeId: String?
    var note: String
    /// Made up to lay out the screen. Never persisted.
    var isPlaceholder: Bool

    init(id: UUID = UUID(), kind: EventKind, at: Date, nodeId: String? = nil, note: String = "", isPlaceholder: Bool = false) {
        self.id = id
        self.kind = kind
        self.at = at
        self.nodeId = nodeId
        self.note = note
        self.isPlaceholder = isPlaceholder
    }
}
