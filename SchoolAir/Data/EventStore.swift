import Foundation
import Observation

/// Event markers people add by hand. Saved as JSON in Application Support.
@MainActor @Observable
final class EventStore {
    private(set) var events: [EventMarker] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? EventStore.defaultURL()
        load()
    }

    func add(_ event: EventMarker) {
        events.append(event)
        events.sort { $0.at < $1.at }
        save()
    }

    func remove(_ event: EventMarker) {
        events.removeAll { $0.id == event.id }
        save()
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("SchoolAir", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("events.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        events = (try? JSONDecoder.schoolAir.decode([EventMarker].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder.schoolAir.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
