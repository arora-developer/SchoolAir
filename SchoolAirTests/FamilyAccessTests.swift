import XCTest
@testable import SchoolAir

final class FamilyAccessTests: XCTestCase {
    let viewer = "abcdefghijklmnopqrstuvwxyz12"
    func testPhoneCodeRoundTripsWithoutChangingCase() {
        XCTAssertEqual(FamilyAccessPolicy.viewerID(from: FamilyAccessPolicy.phoneCode(for: viewer)), viewer)
        XCTAssertEqual(FamilyAccessPolicy.viewerID(from: "  SA1:\(viewer)\n"), viewer)
    }
    func testOwnerAndSensorCannotBeAddedAsViewers() {
        let owner = "OwnerOwnerOwnerOwnerOwner001", sensor = "SensorSensorSensorSensor0001"
        XCTAssertNil(FamilyAccessPolicy.viewerID(from: FamilyAccessPolicy.phoneCode(for: owner), ownerID: owner, sensorID: sensor))
        XCTAssertNil(FamilyAccessPolicy.viewerID(from: FamilyAccessPolicy.phoneCode(for: sensor), ownerID: owner, sensorID: sensor))
        XCTAssertEqual(FamilyAccessPolicy.viewerID(from: FamilyAccessPolicy.phoneCode(for: viewer), ownerID: owner, sensorID: sensor), viewer)
    }
    func testRejectsTruncatedCodesAndDatabasePaths() {
        for bad in [viewer, "SA1:", "sa1:\(viewer)", "SA1:\(viewer)/child", "SA1:abcdefghijklmnopqrstuvwxyz1.", "SA1:abcdefghijklmnopqrstuvwxyé12"] {
            XCTAssertNil(FamilyAccessPolicy.viewerID(from: bad), bad)
        }
    }
    func testPhoneNameMatchesDatabaseLengthAndIsNotBlank() {
        XCTAssertEqual(FamilyAccessPolicy.name(from: " Family phone \n"), "Family phone")
        for bad in ["   ", String(repeating: "a", count: 41), String(repeating: "😀", count: 21), "Family\nphone"] {
            XCTAssertNil(FamilyAccessPolicy.name(from: bad))
        }
        XCTAssertNotNil(FamilyAccessPolicy.name(from: String(repeating: "a", count: 40)))
    }
    @MainActor func testReconnectRestartsReadingsWithoutReplacingSource() {
        let store = AirStore.preview
        let sourceLabel = store.readingSource.label
        store.reconnectSensors()
        XCTAssertEqual(store.connectionAttempt, 1)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.readingSource.label, sourceLabel)
    }
}
