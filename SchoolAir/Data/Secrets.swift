import Foundation

/// Reads `Secrets.plist`, which is gitignored. Copy `Secrets.example.plist` to `Secrets.plist` and fill it in.
/// Missing file or empty values simply mean "not configured"; callers choose their fallback.
enum Secrets {
    static let dictionary: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        return values
    }()

    /// A non-empty string for `key`, or `nil` when the key is missing or blank.
    static func string(_ key: String) -> String? {
        (dictionary[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
