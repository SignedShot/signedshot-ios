import XCTest
@testable import SignedShotSDK

final class SignedShotClientTests: XCTestCase {

    private var client: SignedShotClient!
    private var testKeychain: KeychainStorage!

    override func setUp() {
        super.setUp()
        // Use a unique service name for test isolation
        testKeychain = KeychainStorage(service: "io.signedshot.sdk.tests.\(UUID().uuidString)")
        let config = SignedShotConfiguration(
            baseURL: URL(string: "https://test-api.signedshot.io")!,
            publisherId: "test-publisher-id"
        )
        client = SignedShotClient(configuration: config, keychain: testKeychain)
    }

    override func tearDown() {
        client = nil
        testKeychain = nil
        super.tearDown()
    }

    // MARK: - Registration State Tests

    func testIsDeviceRegisteredWhenNotRegistered() async {
        let isRegistered = await client.isDeviceRegistered
        XCTAssertFalse(isRegistered)
    }

    func testDeviceIdWhenNotRegistered() async {
        let deviceId = await client.deviceId
        XCTAssertNil(deviceId)
    }

    // MARK: - Capture Session Tests

    func testCreateCaptureSessionRequiresRegistration() async {
        do {
            _ = try await client.createCaptureSession()
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as SignedShotAPIError {
            XCTAssertEqual(error, .deviceNotRegistered)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Trust Token Tests

    func testExchangeTrustTokenRequiresRegistration() async {
        do {
            _ = try await client.exchangeTrustToken(nonce: "test-nonce")
            XCTFail("Expected deviceNotRegistered error")
        } catch let error as SignedShotAPIError {
            XCTAssertEqual(error, .deviceNotRegistered)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - SignedShotAPIError Equatable

extension SignedShotAPIError: Equatable {
    public static func == (lhs: SignedShotAPIError, rhs: SignedShotAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.deviceAlreadyRegistered, .deviceAlreadyRegistered),
             (.invalidPublisherId, .invalidPublisherId),
             (.unauthorized, .unauthorized),
             (.notFound, .notFound),
             (.deviceNotRegistered, .deviceNotRegistered),
             (.invalidNonce, .invalidNonce),
             (.sessionExpired, .sessionExpired):
            return true
        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
        default:
            return false
        }
    }
}
