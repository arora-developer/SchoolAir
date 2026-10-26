import Foundation

/// Which kind of box a node is. Matches `kind` under `/nodes/{id}` in Firebase.
enum NodeKind: String, Codable, Hashable, Sendable {
    case indoor
    case portable
}

/// One physical box. Mirrors `/nodes/{id}`: name, kind, location label, schemaVersion.
struct Node: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: NodeKind
    var location: String
    var schemaVersion: Int

    /// The sensor(s) inside, for the source line under each reading.
    var sensorLabel: String {
        switch kind {
        case .indoor: "SCD-41"
        case .portable: "PMSA003I + SHT45"
        }
    }
}

extension Node {
    /// Node ids agreed in the data contract.
    static let indoorID = "home-in"
    static let portableID = "portable"
}
