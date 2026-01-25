import XCTest
@testable import SignedShotSDK

final class SignedShotSDKTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SignedShotSDK.version, "0.1.0")
    }

    func testCapturedPhotoInit() {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic bytes
        let date = Date()
        let id = UUID()

        let photo = CapturedPhoto(jpegData: data, capturedAt: date, captureId: id)

        XCTAssertEqual(photo.jpegData, data)
        XCTAssertEqual(photo.capturedAt, date)
        XCTAssertEqual(photo.captureId, id)
    }

    func testPhotoStorageFilename() {
        let storage = PhotoStorage(folderName: "TestFolder")
        XCTAssertEqual(storage.folderName, "TestFolder")
    }

    func testCaptureErrorDescriptions() {
        XCTAssertNotNil(CaptureError.cameraUnavailable.errorDescription)
        XCTAssertNotNil(CaptureError.permissionDenied.errorDescription)
        XCTAssertNotNil(CaptureError.captureInProgress.errorDescription)
        XCTAssertNotNil(CaptureError.noCameraDevice.errorDescription)
        XCTAssertNotNil(CaptureError.captureFailed("test").errorDescription)
    }
}
