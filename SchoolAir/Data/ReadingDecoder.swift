import Foundation

/// Turns the dictionaries the Firebase SDK hands back into the app's reading types.
/// SDK-free on purpose, so it is unit tested today against the agreed data contract.
enum ReadingDecoder {
    static func indoor(from dictionary: [String: Any]) throws -> IndoorReading {
        try decode(IndoorReading.self, from: dictionary)
    }

    static func portable(from dictionary: [String: Any]) throws -> PortableReading {
        try decode(PortableReading.self, from: dictionary)
    }

    /// `/nodes/{id}`: the id is the key, not a field, so it is injected here.
    static func node(id: String, from dictionary: [String: Any]) throws -> Node {
        var withID = dictionary
        withID["id"] = id
        return try decode(Node.self, from: withID)
    }

    /// `/readings/{id}` comes back as `{autoId: reading}`. Sorted by `t`; push ids are only roughly chronological.
    static func indoorHistory(from dictionary: [String: Any]) -> [IndoorReading] {
        dictionary.values
            .compactMap { $0 as? [String: Any] }
            .compactMap { try? indoor(from: $0) }
            .sorted { $0.t < $1.t }
    }

    static func portableHistory(from dictionary: [String: Any]) -> [PortableReading] {
        dictionary.values
            .compactMap { $0 as? [String: Any] }
            .compactMap { try? portable(from: $0) }
            .sorted { $0.t < $1.t }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try JSONDecoder.schoolAir.decode(T.self, from: data)
    }
}
