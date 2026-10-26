import XCTest
import CoreLocation
@testable import SchoolAir

private final class LocationManagerSpy: CLLocationManager {
    var status: CLAuthorizationStatus = .authorizedWhenInUse
    var requests = 0
    var permissionRequests = 0
    var stops = 0
    override var authorizationStatus: CLAuthorizationStatus { status }
    override func requestLocation() { requests += 1 }
    override func requestWhenInUseAuthorization() { permissionRequests += 1 }
    override func stopUpdatingLocation() { stops += 1 }
}

@MainActor
final class PhoneLocationTests: XCTestCase {
    private func harness(status: CLAuthorizationStatus = .authorizedWhenInUse) -> (PortableLocation, LocationManagerSpy, UserDefaults) {
        let suite = "SchoolAir.LocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let manager = LocationManagerSpy()
        manager.status = status
        let location = PortableLocation(manager: manager, defaults: defaults, resolveName: { _, _ in })
        location.setForeground(true)
        return (location, manager, defaults)
    }
    private func measurement(latitude: Double = 38, age: TimeInterval = 0, accuracy: Double = 25) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: Date().addingTimeInterval(-age))
    }
    private func capture(_ location: PortableLocation, _ manager: LocationManagerSpy) {
        location.saveNearbyLocation()
        location.locationManager(manager, didUpdateLocations: [measurement()])
    }

    func testOnlyExplicitButtonRequestsPermissionOrLocation() {
        let (location, manager, _) = harness(status: .notDetermined)
        XCTAssertEqual(manager.permissionRequests, 0)
        XCTAssertEqual(manager.requests, 0)
        location.saveNearbyLocation()
        XCTAssertEqual(manager.permissionRequests, 1)
        manager.status = .authorizedWhenInUse
        location.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.requests, 1)
        location.saveNearbyLocation()
        XCTAssertEqual(manager.requests, 1)
    }

    func testSavedLocationSurvivesRelaunchWithoutAnotherGPSRequest() {
        let (location, manager, defaults) = harness()
        capture(location, manager)
        let nextManager = LocationManagerSpy()
        let restored = PortableLocation(manager: nextManager, defaults: defaults, resolveName: { _, _ in })
        restored.setForeground(true)
        XCTAssertNotNil(restored.saved)
        XCTAssertEqual(restored.saved, location.saved)
        XCTAssertEqual(nextManager.requests, 0)
        XCTAssertFalse(restored.isLocating)
    }

    func testWalkingAwayCannotMoveTheSavedBox() {
        let (location, manager, _) = harness()
        capture(location, manager)
        let saved = location.saved
        location.locationManager(manager, didUpdateLocations: [measurement(latitude: 40)])
        location.setForeground(false)
        location.setForeground(true)
        XCTAssertEqual(location.saved, saved)
        XCTAssertEqual(manager.requests, 1)
    }

    func testExplicitUpdateReplacesSavedSpot() {
        let (location, manager, _) = harness()
        capture(location, manager)
        location.saveNearbyLocation()
        location.locationManager(manager, didUpdateLocations: [measurement(latitude: 40)])
        XCTAssertEqual(location.saved?.fix.latitude, 40)
        XCTAssertEqual(manager.requests, 2)
    }

    func testFailureKeepsPreviousSavedSpot() {
        let (location, manager, _) = harness()
        capture(location, manager)
        let saved = location.saved
        location.saveNearbyLocation()
        location.locationManager(manager, didFailWithError: CLError(.locationUnknown))
        XCTAssertEqual(location.saved, saved)
        XCTAssertFalse(location.isLocating)
    }

    func testDeniedAccessDoesNotEraseSavedSpot() {
        let (location, manager, _) = harness()
        capture(location, manager)
        let saved = location.saved
        manager.status = .denied
        location.locationManagerDidChangeAuthorization(manager)
        location.saveNearbyLocation()
        XCTAssertTrue(location.needsSettings)
        XCTAssertEqual(location.saved, saved)
        XCTAssertEqual(manager.requests, 1)
        XCTAssertFalse(location.isLocating)
    }

    func testPermissionRevokedDuringCaptureCancelsIt() {
        let (location, manager, _) = harness()
        location.saveNearbyLocation()
        manager.status = .denied
        location.locationManagerDidChangeAuthorization(manager)
        location.locationManager(manager, didUpdateLocations: [measurement()])
        XCTAssertFalse(location.isLocating)
        XCTAssertNil(location.saved)
    }

    func testBackgroundCancelsPendingCaptureAndDoesNotRestartIt() {
        let (location, manager, _) = harness()
        location.saveNearbyLocation()
        location.setForeground(false)
        location.locationManager(manager, didUpdateLocations: [measurement()])
        location.setForeground(true)
        XCTAssertNil(location.saved)
        XCTAssertFalse(location.isLocating)
        XCTAssertEqual(manager.requests, 1)
        XCTAssertGreaterThan(manager.stops, 0)
    }

    func testOldCachedFixCannotReplaceSavedSpot() {
        let (location, manager, _) = harness()
        capture(location, manager)
        let saved = location.saved
        location.saveNearbyLocation()
        location.locationManager(manager, didUpdateLocations: [measurement(latitude: 40, age: 60)])
        XCTAssertEqual(location.saved, saved)
        XCTAssertNotNil(location.message)
    }

    func testClearRemovesPersistentPin() {
        let (location, manager, defaults) = harness()
        capture(location, manager)
        location.clearSavedLocation()
        let restored = PortableLocation(manager: LocationManagerSpy(), defaults: defaults, resolveName: { _, _ in })
        XCTAssertNil(restored.saved)
        XCTAssertEqual(restored.label, "Set box location")
    }

    func testFreshApproximateFixAcceptedButInvalidAndStaleFixesRejected() {
        let now = Date()
        func fix(age: TimeInterval = 0, accuracy: Double = 25, latitude: Double = 38) -> PhoneLocationFix {
            PhoneLocationFix(latitude: latitude, longitude: -87, accuracy: accuracy, timestamp: now.addingTimeInterval(-age))
        }
        XCTAssertTrue(fix(accuracy: 4_000).isUsable(at: now))
        XCTAssertFalse(fix(age: 31).isUsable(at: now))
        XCTAssertFalse(fix(age: -31).isUsable(at: now))
        XCTAssertFalse(fix(accuracy: -1).isUsable(at: now))
        XCTAssertFalse(fix(accuracy: 5_001).isUsable(at: now))
        XCTAssertFalse(fix(latitude: .nan).isUsable(at: now))
    }
}
