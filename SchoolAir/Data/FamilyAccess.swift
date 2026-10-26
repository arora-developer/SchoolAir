import Foundation
import Observation
import FirebaseAuth
import FirebaseDatabase

/// Firebase Auth UIDs of the owner phone and of the sensor uploader. These are account identifiers,
/// not credentials: Firebase rules enforce every permission. They are read from `Secrets.plist`
/// (gitignored, see `Secrets.example.plist`) so the repository carries no real account IDs.
/// With no owner configured, every phone is a viewer and nobody can approve access.
enum FamilyAccessPolicy {
    static let ownerID = Secrets.string("FIREBASE_OWNER_UID") ?? ""
    static let sensorID = Secrets.string("FIREBASE_SENSOR_UID") ?? ""

    static func phoneCode(for uid: String) -> String { "SA1:\(uid)" }
    static func viewerID(from code: String, ownerID: String = FamilyAccessPolicy.ownerID,
                         sensorID: String = FamilyAccessPolicy.sensorID) -> String? {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("SA1:") else { return nil }
        let uid = String(text.dropFirst(4))
        guard uid.count == 28, uid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              uid != ownerID, uid != sensorID else { return nil }
        return uid
    }
    static func name(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 40,
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return text
    }
}

@MainActor @Observable
final class FamilyAccess {
    private(set) var uid: String?
    private(set) var viewers: [String: String] = [:]
    private(set) var allowed = false
    private(set) var ready = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var message: String?
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var query: DatabaseReference?
    @ObservationIgnored private var handle: DatabaseHandle?

    var isOwner: Bool { !FamilyAccessPolicy.ownerID.isEmpty && uid == FamilyAccessPolicy.ownerID }
    var code: String? { uid.map(FamilyAccessPolicy.phoneCode) }

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in self?.observe(user?.uid) }
        }
    }

    func stop() {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        authHandle = nil
        detach()
    }

    private func detach() {
        if let handle { query?.removeObserver(withHandle: handle) }
        handle = nil; query = nil
    }

    private func observe(_ id: String?) {
        detach()
        uid = id; ready = false; allowed = isOwner; viewers = [:]; error = nil
        guard let id else { return }
        let ref = Database.database().reference().child("viewers")
        query = isOwner ? ref : ref.child(id)
        handle = query?.observe(.value, with: { [weak self] snapshot in
            let value = snapshot.value
            Task { @MainActor [weak self] in
                guard let self, self.uid == id, self.authHandle != nil else { return }
                self.ready = true; self.error = nil
                if self.isOwner { self.viewers = value as? [String: String] ?? [:] }
                else { self.allowed = value is String }
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.uid == id, self.authHandle != nil else { return }
                self.ready = true
                self.error = "Family access is unavailable. Check your connection and the Firebase setup."
            }
        })
    }

    func add(code: String, name: String) async {
        guard isOwner, !busy else { return }
        guard let viewer = FamilyAccessPolicy.viewerID(from: code), let label = FamilyAccessPolicy.name(from: name) else {
            error = "Paste the complete code from the other phone and enter a name of up to 40 characters."
            return
        }
        busy = true; error = nil; message = nil
        defer { busy = false }
        do {
            try await Database.database().reference().child("viewers").child(viewer).setValue(label)
            message = "\(label) can now view the sensors. Open Family access on that phone and tap Connect to sensors."
        } catch { self.error = "Could not save access. Check your connection and try again." }
    }

    func remove(_ viewer: String) async {
        guard isOwner, !busy, viewers[viewer] != nil else { return }
        busy = true; error = nil; message = nil
        defer { busy = false }
        do {
            try await Database.database().reference().child("viewers").child(viewer).removeValue()
            message = "Access removed. Previously viewed readings cannot be taken back."
        } catch { self.error = "Could not remove access. Check your connection and try again." }
    }
}
