import Foundation
import FirebaseAuth
import FirebaseDatabase

/// Authenticate before attaching listeners. Keep each phone’s saved identity: the owner approves family viewers.
final class FirebaseReadingSource: ReadingSource {
    let label = "Firebase (live)"

    func snapshots() -> AsyncStream<AirSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let session = FirebaseSession(continuation: continuation)
            let task = Task { @MainActor in
                do {
                    if Auth.auth().currentUser == nil {
                        _ = try await Auth.auth().signInAnonymously()
                    }
                    guard !Task.isCancelled else { return }
                    session.start()
                } catch {
                    session.failAuthentication()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                session.stop()
            }
        }
    }
}

/// All decoding and history work runs on a serial background queue, never the UI thread.
private final class FirebaseSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SchoolAir.firebase", qos: .userInitiated)
    private let continuation: AsyncStream<AirSnapshot>.Continuation
    private var observers: [(DatabaseQuery, DatabaseHandle)] = []
    private var stopped = false
    private var pending: DispatchWorkItem?
    private var indoor: [String: IndoorReading] = [:]
    private var portable: [String: PortableReading] = [:]
    private var state = AirSnapshot(
        nodes: [Node(id: Node.indoorID, name: "Indoor box", kind: .indoor, location: "Home", schemaVersion: 1),
                Node(id: Node.portableID, name: "Portable box", kind: .portable, location: "Location not recorded", schemaVersion: 1)],
        latestIndoor: nil, latestPortable: nil, indoorHistory: [], portableHistory: [],
        placeholderEvents: [], provenance: .live, receivedAt: Date())

    init(continuation: AsyncStream<AirSnapshot>.Continuation) { self.continuation = continuation }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            let root = Database.database().reference()
            observe(root.child(".info/connected"), event: .value, name: "connection") { [self] value, _ in
                state.connected = value as? Bool ?? false
            }
            observe(root.child("latest/home-in"), event: .value, name: "Indoor reading") { [self] value, _ in
                state.latestIndoor = try (value as? [String: Any]).map(ReadingDecoder.indoor)
            }
            observe(root.child("latest/portable"), event: .value, name: "Portable reading") { [self] value, _ in
                state.latestPortable = try (value as? [String: Any]).map(ReadingDecoder.portable)
            }
            // Push keys are chronological and indexed by default. Bound the download without changing rules.
            // Seven days at five seconds indoors, ten seconds on the portable box.
            attachHistory(root.child("readings/home-in").queryOrderedByKey().queryLimited(toLast: 125_000), isIndoor: true)
            attachHistory(root.child("readings/portable").queryOrderedByKey().queryLimited(toLast: 65_000), isIndoor: false)
        }
    }

    private func observe(_ query: DatabaseQuery, event: DataEventType, name: String,
                         apply: @escaping (Any?, String) throws -> Void) {
        let handle = query.observe(event, with: { [weak self] snapshot in
            guard let self else { return }
            let value = snapshot.value
            let key = snapshot.key
            self.queue.async { [self] in
                guard !self.stopped else { return }
                do {
                    try apply(value, key)
                    self.state.issues.removeValue(forKey: name)
                } catch {
                    self.state.issues[name] = "Could not decode \(name.lowercased()). Check the sensor's data format."
                }
                self.schedulePublish()
            }
        }, withCancel: { [weak self] _ in
            guard let self else { return }
            self.queue.async { [self] in
                guard !self.stopped else { return }
                // A denied/revoked stream must stop presenting its cached measurements as live.
                if name == "Indoor reading" { self.state.latestIndoor = nil }
                if name == "Portable reading" { self.state.latestPortable = nil }
                if name == "Indoor history" { self.indoor.removeAll() }
                if name == "Portable history" { self.portable.removeAll() }
                self.state.issues[name] = "\(name) read denied. Open Family access on Sensors to connect this phone."
                self.schedulePublish()
            }
        })
        observers.append((query, handle))
    }

    private func attachHistory(_ query: DatabaseQuery, isIndoor: Bool) {
        let name = isIndoor ? "Indoor history" : "Portable history"
        for event in [DataEventType.childAdded, .childChanged, .childRemoved] {
            observe(query, event: event, name: name) { [self] value, key in
                if event == .childRemoved {
                    if isIndoor { indoor.removeValue(forKey: key) }
                    else { portable.removeValue(forKey: key) }
                } else if let dictionary = value as? [String: Any] {
                    if isIndoor { indoor[key] = try ReadingDecoder.indoor(from: dictionary) }
                    else { portable[key] = try ReadingDecoder.portable(from: dictionary) }
                }
            }
        }
    }

    private func schedulePublish() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !stopped else { return }
            pending = nil
            let cutoff = Date().addingTimeInterval(-7 * 86_400)
            indoor = indoor.filter { $0.value.t >= cutoff }
            portable = portable.filter { $0.value.t >= cutoff }
            state.indoorHistory = indoor.values.sorted { $0.t < $1.t }
            state.portableHistory = portable.values.sorted { $0.t < $1.t }
            state.receivedAt = Date()
            continuation.yield(state)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func failAuthentication() {
        queue.async { [self] in
            guard !stopped else { return }
            state.issues["Sign-in"] = "Firebase sign-in failed. Check your connection and retry."
            continuation.yield(state)
            continuation.finish()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            pending?.cancel()
            for (query, handle) in observers { query.removeObserver(withHandle: handle) }
            observers.removeAll()
        }
    }
}

