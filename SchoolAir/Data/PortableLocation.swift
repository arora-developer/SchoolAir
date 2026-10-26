import CoreLocation
import Foundation
import Observation

struct PhoneLocationFix: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date

    /// Only a fresh phone fix may be used to set a new box location.
    func isUsable(at now: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
        && (-180...180).contains(longitude) && accuracy >= 0 && accuracy <= 5_000
        && now.timeIntervalSince(timestamp) >= -30 && now.timeIntervalSince(timestamp) <= 30
    }
}

struct SavedBoxLocation: Codable, Equatable {
    let id: UUID
    let fix: PhoneLocationFix
    let savedAt: Date
    var place: String?
}

/// User-confirmed placement, stored on this phone. Never follows later phone movement.
@MainActor @Observable
final class PortableLocation: NSObject, CLLocationManagerDelegate {
    private(set) var saved: SavedBoxLocation?
    private(set) var isLocating = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var message: String?
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private let resolveName: ((CLLocation, @escaping (String?) -> Void) -> Void)?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var requestStarted = false
    private static let storageKey = "portableBox.savedLocation.v1"

    init(manager: CLLocationManager = CLLocationManager(), defaults: UserDefaults = .standard,
         resolveName: ((CLLocation, @escaping (String?) -> Void) -> Void)? = nil) {
        self.manager = manager
        self.defaults = defaults
        self.resolveName = resolveName
        if let data = defaults.data(forKey: Self.storageKey) {
            saved = try? JSONDecoder().decode(SavedBoxLocation.self, from: data)
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorization = manager.authorizationStatus
    }

    var needsSettings: Bool { authorization == .denied || authorization == .restricted }
    var label: String {
        guard let saved else { return isLocating ? "Saving location…" : "Set box location" }
        return "Saved · \(saved.place ?? "Box location")"
    }

    /// The user confirms the box is next to the phone before this one-shot request.
    func saveNearbyLocation() {
        guard !isLocating else { return }
        guard foreground else { message = "Open the app while standing next to the box."; return }
        message = nil
        isLocating = true
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        requestIfAuthorized()
    }

    func cancelCapture() {
        manager.stopUpdatingLocation()
        isLocating = false
        requestStarted = false
    }

    func clearSavedLocation() {
        cancelCapture()
        geocoder.cancelGeocode()
        saved = nil
        message = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if !active && isLocating {
            cancelCapture()
            message = "Location wasn't saved. Try again when you're next to the box."
        }
    }

    private func requestIfAuthorized() {
        guard foreground, isLocating else { return }
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            guard !requestStarted else { return }
            requestStarted = true
            manager.requestLocation()
        case .denied, .restricted:
            cancelCapture()
            message = "Allow location access to save where the box is."
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        requestIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard foreground, isLocating, requestStarted else { return }
        let now = Date()
        let location = locations.reversed().first { location in
            PhoneLocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                             accuracy: location.horizontalAccuracy, timestamp: location.timestamp).isUsable(at: now)
        }
        cancelCapture()
        guard let location else {
            message = "Couldn't get a fresh location. Stand next to the box and try again."
            return
        }
        let fix = PhoneLocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                   accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
        let id = UUID()
        saved = SavedBoxLocation(id: id, fix: fix, savedAt: now, place: nil)
        persist()
        message = "Box location saved. It will stay here until you update it."
        geocoder.cancelGeocode()
        let complete: (String?) -> Void = { [weak self] name in
            guard let owner = self else { return }
            Task { @MainActor in
                guard owner.saved?.id == id else { return }
                owner.saved?.place = name
                owner.persist()
            }
        }
        if let resolveName { resolveName(location, complete) }
        else {
            geocoder.reverseGeocodeLocation(location) { marks, _ in
                let mark = marks?.first
                let parts = [mark?.name, mark?.locality].compactMap { $0 }
                let unique = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                complete(unique.isEmpty ? nil : unique.joined(separator: ", "))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLocating else { return }
        cancelCapture()
        authorization = manager.authorizationStatus
        message = needsSettings ? "Allow location access to save where the box is." : "Location unavailable. Your saved spot hasn't changed. Try again."
    }

    private func persist() {
        guard let saved, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
