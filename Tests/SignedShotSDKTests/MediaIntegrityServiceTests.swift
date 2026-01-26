import XCTest
@testable import SignedShotSDK

final class MediaIntegrityServiceTests: XCTestCase {
    private var enclaveService: SecureEnclaveService!
    private var integrityService: MediaIntegrityService!
    private let testKeyTag = "io.signedshot.sdk.test.integrity.key"

    override func setUp() {
        super.setUp()
        enclaveService = SecureEnclaveService(keyTag: testKeyTag)
        integrityService = MediaIntegrityService(enclaveService: enclaveService)
        // Clean up any existing test key
        try? enclaveService.deleteKey()
    }

    override func tearDown() {
        try? enclaveService.deleteKey()
        enclaveService = nil
        integrityService = nil
        super.tearDown()
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(MediaIntegrityError.hashMismatch.errorDescription)
        XCTAssertNotNil(MediaIntegrityError.invalidSignature.errorDescription)
    }

    // MARK: - Hash Tests (no Secure Enclave needed)

    func testComputeHashReturns64CharHex() {
        let data = Data("Hello, SignedShot!".utf8)
        let hash = integrityService.computeHash(for: data)

        XCTAssertEqual(hash.count, 64)
        // Verify it's valid hex
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testComputeHashIsConsistent() {
        let data = Data("Test data".utf8)
        let hash1 = integrityService.computeHash(for: data)
        let hash2 = integrityService.computeHash(for: data)

        XCTAssertEqual(hash1, hash2)
    }

    func testComputeHashDifferentDataDifferentHash() {
        let data1 = Data("Data 1".utf8)
        let data2 = Data("Data 2".utf8)

        let hash1 = integrityService.computeHash(for: data1)
        let hash2 = integrityService.computeHash(for: data2)

        XCTAssertNotEqual(hash1, hash2)
    }

    func testComputeHashEmptyData() {
        let data = Data()
        let hash = integrityService.computeHash(for: data)

        // SHA-256 of empty data is well-known
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testComputeHashKnownValue() {
        // "hello" has a well-known SHA-256
        let data = Data("hello".utf8)
        let hash = integrityService.computeHash(for: data)

        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    // MARK: - Message Building Tests

    func testBuildMessage() {
        let message = integrityService.buildMessage(
            contentHash: "abc123",
            captureId: "uuid-456",
            capturedAt: "2026-01-26T12:00:00Z"
        )

        XCTAssertEqual(message, "abc123:uuid-456:2026-01-26T12:00:00Z")
    }

    func testBuildMessageFormat() {
        let contentHash = "a" * 64
        let captureId = "550e8400-e29b-41d4-a716-446655440000"
        let capturedAt = "2026-01-26T15:30:00Z"

        let message = integrityService.buildMessage(
            contentHash: contentHash,
            captureId: captureId,
            capturedAt: capturedAt
        )

        // Verify exact format: hash:captureId:capturedAt
        let expected = "\(contentHash):\(captureId):\(capturedAt)"
        XCTAssertEqual(message, expected)
        XCTAssertTrue(message.hasPrefix(contentHash))
        XCTAssertTrue(message.contains(captureId))
        XCTAssertTrue(message.hasSuffix(capturedAt))
    }

    // MARK: - MediaIntegrity Codable Tests

    func testMediaIntegrityCodable() throws {
        let integrity = MediaIntegrity(
            contentHash: "abc123def456",
            signature: "c2lnbmF0dXJl",
            publicKey: "cHVibGljS2V5",
            captureId: "uuid-789",
            capturedAt: "2026-01-26T12:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(integrity)
        let json = String(data: data, encoding: .utf8)!

        // Verify snake_case keys
        XCTAssertTrue(json.contains("content_hash"))
        XCTAssertTrue(json.contains("public_key"))
        XCTAssertTrue(json.contains("capture_id"))
        XCTAssertTrue(json.contains("captured_at"))

        // Verify round-trip
        let decoded = try JSONDecoder().decode(MediaIntegrity.self, from: data)
        XCTAssertEqual(decoded.contentHash, integrity.contentHash)
        XCTAssertEqual(decoded.signature, integrity.signature)
        XCTAssertEqual(decoded.publicKey, integrity.publicKey)
        XCTAssertEqual(decoded.captureId, integrity.captureId)
        XCTAssertEqual(decoded.capturedAt, integrity.capturedAt)
    }

    // MARK: - Integration Tests (require real device)

    func testGenerateIntegrity() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        // Create Secure Enclave key
        try enclaveService.createKey()

        // Generate integrity
        let testData = Data("Test JPEG content".utf8)
        let captureId = UUID()
        let capturedAt = Date()

        let integrity = try integrityService.generateIntegrity(
            for: testData,
            captureId: captureId,
            capturedAt: capturedAt
        )

        // Verify hash
        XCTAssertEqual(integrity.contentHash.count, 64)
        XCTAssertEqual(integrity.contentHash, integrityService.computeHash(for: testData))

        // Verify captureId
        XCTAssertEqual(integrity.captureId, captureId.uuidString)

        // Verify capturedAt is ISO8601
        XCTAssertTrue(integrity.capturedAt.contains("T"))
        XCTAssertTrue(integrity.capturedAt.hasSuffix("Z"))

        // Verify signature is base64
        XCTAssertNotNil(Data(base64Encoded: integrity.signature))

        // Verify public key is base64
        XCTAssertNotNil(Data(base64Encoded: integrity.publicKey))
        #endif
    }

    func testGenerateAndVerifyIntegrity() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        try enclaveService.createKey()

        let testData = Data("Authentic media content".utf8)
        let integrity = try integrityService.generateIntegrity(
            for: testData,
            captureId: UUID(),
            capturedAt: Date()
        )

        // Verify passes with correct data
        let isValid = try integrityService.verify(integrity: integrity, for: testData)
        XCTAssertTrue(isValid)

        // Verify fails with wrong data
        let wrongData = Data("Tampered content".utf8)
        let isInvalid = try integrityService.verify(integrity: integrity, for: wrongData)
        XCTAssertFalse(isInvalid)
        #endif
    }

    func testGenerateIntegrityWithStringCaptureId() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        try enclaveService.createKey()

        let testData = Data("Test content".utf8)
        let captureIdString = "custom-capture-id-123"

        let integrity = try integrityService.generateIntegrity(
            for: testData,
            captureId: captureIdString,
            capturedAt: Date()
        )

        XCTAssertEqual(integrity.captureId, captureIdString)
        #endif
    }

    func testIntegrityTimestampFormat() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Secure Enclave not available on simulator")
        #else
        try enclaveService.createKey()

        // Use a specific date
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 1,
            day: 26,
            hour: 15,
            minute: 30,
            second: 0
        )
        let date = Calendar.current.date(from: components)!

        let integrity = try integrityService.generateIntegrity(
            for: Data("test".utf8),
            captureId: UUID(),
            capturedAt: date
        )

        // Should be ISO8601 format: 2026-01-26T15:30:00Z
        XCTAssertEqual(integrity.capturedAt, "2026-01-26T15:30:00Z")
        #endif
    }
}

// Helper for creating repeated strings
private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}
