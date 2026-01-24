import XCTest
@testable import SignedShotSDK

final class SignedShotSDKTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(SignedShotSDK.version, "0.1.0")
    }
}
