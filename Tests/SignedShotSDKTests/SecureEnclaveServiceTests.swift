import XCTest
@testable import SignedShotSDK

final class SecureEnclaveServiceTests: XCTestCase {
    private var service: SecureEnclaveService!
    private let testKeyTag = "io.signedshot.sdk.test.enclave.key"

    override func setUp() {
        super.setUp()
        service = SecureEnclaveService(keyTag: testKeyTag)
        // Clean up any existing test key
        try? service.deleteKey()
    }

    override func tearDown() {
        // Clean up test key after each test
        try? service.deleteKey()
        service = nil
        super.tearDown()
    }

    // MARK: - Error Description Tests (always work, no hardware needed)

    func testErrorDescriptions() {
        XCTAssertNotNil(SecureEnclaveError.keyAlreadyExists.errorDescription)
        XCTAssertNotNil(SecureEnclaveError.keyNotFound.errorDescription)
        XCTAssertNotNil(SecureEnclaveError.keyCreationFailed(nil).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.keyDeletionFailed(0).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.accessControlCreationFailed(nil).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.publicKeyExtractionFailed.errorDescription)
        XCTAssertNotNil(SecureEnclaveError.publicKeyExportFailed(nil).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.signingFailed(nil).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.verificationFailed(nil).errorDescription)
        XCTAssertNotNil(SecureEnclaveError.encodingFailed.errorDescription)
    }

    func testServiceInitialization() {
        let customTag = "custom.test.tag"
        let customService = SecureEnclaveService(keyTag: customTag)
        XCTAssertNotNil(customService)
    }

    func testDefaultKeyTag() {
        let defaultService = SecureEnclaveService()
        XCTAssertNotNil(defaultService)
    }

    // MARK: - Secure Enclave Tests (require real device)
    // These tests will fail on simulator since Secure Enclave is not available

    func testKeyExistsReturnsFalseWhenNoKey() {
        // This should work even on simulator - it's just a query
        XCTAssertFalse(service.keyExists())
    }

    func testGetPublicKeyThrowsWhenNoKey() {
        XCTAssertThrowsError(try service.getPublicKey()) { error in
            guard let enclaveError = error as? SecureEnclaveError else {
                XCTFail("Expected SecureEnclaveError")
                return
            }
            XCTAssertEqual(enclaveError.errorDescription, SecureEnclaveError.keyNotFound.errorDescription)
        }
    }

    func testGetPublicKeyDataThrowsWhenNoKey() {
        XCTAssertThrowsError(try service.getPublicKeyData()) { error in
            XCTAssertTrue(error is SecureEnclaveError)
        }
    }

    func testGetPublicKeyBase64ThrowsWhenNoKey() {
        XCTAssertThrowsError(try service.getPublicKeyBase64()) { error in
            XCTAssertTrue(error is SecureEnclaveError)
        }
    }

    func testSignThrowsWhenNoKey() {
        let testData = Data("test message".utf8)
        XCTAssertThrowsError(try service.sign(data: testData)) { error in
            XCTAssertTrue(error is SecureEnclaveError)
        }
    }

    func testSignMessageThrowsWhenNoKey() {
        XCTAssertThrowsError(try service.sign(message: "test message")) { error in
            XCTAssertTrue(error is SecureEnclaveError)
        }
    }

    func testDeleteKeySucceedsWhenNoKey() throws {
        // On simulator, Keychain operations may fail with -34018 (missing entitlement)
        // This test verifies the delete operation doesn't throw keyNotFound
        #if targetEnvironment(simulator)
        // On simulator, we just verify the method can be called without crashing
        // The actual Keychain behavior varies by simulator configuration
        do {
            try service.deleteKey()
        } catch SecureEnclaveError.keyDeletionFailed {
            // Expected on simulator without proper entitlements
        }
        #else
        // Delete should succeed even when key doesn't exist
        XCTAssertNoThrow(try service.deleteKey())
        #endif
    }

    // MARK: - Integration Tests (require real device with Secure Enclave)
    // These tests are skipped on simulator

    func testCreateKeyAndVerify() throws {
        // Skip on simulator
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        // Create key
        try service.createKey()
        XCTAssertTrue(service.keyExists())

        // Get public key
        let publicKeyData = try service.getPublicKeyData()
        XCTAssertEqual(publicKeyData.count, 65) // Uncompressed P-256 point: 0x04 + 32 + 32

        // First byte should be 0x04 (uncompressed point marker)
        XCTAssertEqual(publicKeyData[0], 0x04)

        // Get base64 representation
        let base64 = try service.getPublicKeyBase64()
        XCTAssertFalse(base64.isEmpty)
        #endif
    }

    func testCreateKeyFailsWhenKeyExists() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        // Create first key
        try service.createKey()

        // Try to create again - should fail
        XCTAssertThrowsError(try service.createKey()) { error in
            guard let enclaveError = error as? SecureEnclaveError else {
                XCTFail("Expected SecureEnclaveError")
                return
            }
            XCTAssertEqual(enclaveError.errorDescription, SecureEnclaveError.keyAlreadyExists.errorDescription)
        }
        #endif
    }

    func testSignAndVerify() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        // Create key
        try service.createKey()

        // Sign data
        let testData = Data("Hello, SignedShot!".utf8)
        let signature = try service.sign(data: testData)

        // Signature should be non-empty (DER encoded ECDSA signature)
        XCTAssertFalse(signature.isEmpty)
        // ECDSA signatures are typically 70-72 bytes in DER format
        XCTAssertGreaterThan(signature.count, 60)
        XCTAssertLessThan(signature.count, 80)

        // Verify signature
        let isValid = try service.verify(signature: signature, for: testData)
        XCTAssertTrue(isValid)

        // Verify fails with wrong data
        let wrongData = Data("Wrong data".utf8)
        let isInvalid = try service.verify(signature: signature, for: wrongData)
        XCTAssertFalse(isInvalid)
        #endif
    }

    func testSignMessage() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        try service.createKey()

        let message = "Test message for signing"
        let signature = try service.sign(message: message)

        XCTAssertFalse(signature.isEmpty)

        // Verify with the same message as data
        let messageData = Data(message.utf8)
        let isValid = try service.verify(signature: signature, for: messageData)
        XCTAssertTrue(isValid)
        #endif
    }

    func testSignBase64() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        try service.createKey()

        let testData = Data("Base64 test".utf8)
        let base64Signature = try service.signBase64(data: testData)

        XCTAssertFalse(base64Signature.isEmpty)

        // Verify it's valid base64
        let decodedSignature = Data(base64Encoded: base64Signature)
        XCTAssertNotNil(decodedSignature)
        #endif
    }

    func testDeleteKey() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        // Create and then delete
        try service.createKey()
        XCTAssertTrue(service.keyExists())

        try service.deleteKey()
        XCTAssertFalse(service.keyExists())

        // Operations should fail after delete
        XCTAssertThrowsError(try service.getPublicKey())
        #endif
    }

    func testMultipleServicesWithDifferentTags() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        let service1 = SecureEnclaveService(keyTag: "io.signedshot.test.key1")
        let service2 = SecureEnclaveService(keyTag: "io.signedshot.test.key2")

        defer {
            try? service1.deleteKey()
            try? service2.deleteKey()
        }

        // Create keys for both services
        try service1.createKey()
        try service2.createKey()

        // Both should exist independently
        XCTAssertTrue(service1.keyExists())
        XCTAssertTrue(service2.keyExists())

        // Delete one, other should still exist
        try service1.deleteKey()
        XCTAssertFalse(service1.keyExists())
        XCTAssertTrue(service2.keyExists())
        #endif
    }
}
