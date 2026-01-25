import XCTest
@testable import SignedShotSDK

final class APIModelsTests: XCTestCase {

    // MARK: - DeviceCreateRequest Tests

    func testDeviceCreateRequestEncoding() throws {
        let request = DeviceCreateRequest(externalId: "test-device-123")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["external_id"] as? String, "test-device-123")
    }

    func testDeviceCreateRequestDecoding() throws {
        let json = """
        {"external_id": "my-device-id"}
        """

        let decoder = JSONDecoder()
        let request = try decoder.decode(DeviceCreateRequest.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(request.externalId, "my-device-id")
    }

    // MARK: - DeviceCreateResponse Tests

    func testDeviceCreateResponseDecoding() throws {
        let json = """
        {
            "device_id": "550e8400-e29b-41d4-a716-446655440000",
            "publisher_id": "660e8400-e29b-41d4-a716-446655440001",
            "external_id": "test-device",
            "device_token": "secret-token-12345",
            "created_at": "2024-01-15T10:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(DeviceCreateResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.deviceId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(response.publisherId, "660e8400-e29b-41d4-a716-446655440001")
        XCTAssertEqual(response.externalId, "test-device")
        XCTAssertEqual(response.deviceToken, "secret-token-12345")
        XCTAssertNotNil(response.createdAt)
    }

    // MARK: - CaptureSessionResponse Tests

    func testCaptureSessionResponseDecoding() throws {
        let json = """
        {
            "capture_id": "abc123-capture-id",
            "nonce": "random-nonce-value",
            "expires_at": "2024-01-15T10:35:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(CaptureSessionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.captureId, "abc123-capture-id")
        XCTAssertEqual(response.nonce, "random-nonce-value")
        XCTAssertNotNil(response.expiresAt)
    }

    // MARK: - TrustRequest Tests

    func testTrustRequestEncoding() throws {
        let request = TrustRequest(nonce: "my-nonce-123")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["nonce"] as? String, "my-nonce-123")
    }

    // MARK: - TrustResponse Tests

    func testTrustResponseDecoding() throws {
        let json = """
        {"trust_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.signature"}
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(TrustResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.trustToken, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.signature")
    }

    // MARK: - SignedShotAPIError Tests

    func testAPIErrorDescriptions() {
        XCTAssertNotNil(SignedShotAPIError.invalidURL.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.networkError(URLError(.notConnectedToInternet)).errorDescription)
        XCTAssertNotNil(SignedShotAPIError.httpError(statusCode: 500, message: "Server error").errorDescription)
        XCTAssertNotNil(SignedShotAPIError.httpError(statusCode: 500, message: nil).errorDescription)
        let decodingErr = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))
        XCTAssertNotNil(SignedShotAPIError.decodingError(decodingErr).errorDescription)
        XCTAssertNotNil(SignedShotAPIError.deviceAlreadyRegistered.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.invalidPublisherId.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.unauthorized.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.notFound.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.deviceNotRegistered.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.invalidNonce.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.sessionExpired.errorDescription)
    }

    // MARK: - SignedShotConfiguration Tests

    func testConfigurationInit() {
        let url = URL(string: "https://api.example.com")!
        let config = SignedShotConfiguration(baseURL: url, publisherId: "pub-123")

        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.publisherId, "pub-123")
    }

    func testConfigurationInitWithString() {
        let config = SignedShotConfiguration(baseURLString: "https://api.example.com", publisherId: "pub-123")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.baseURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(config?.publisherId, "pub-123")
    }

    func testConfigurationInitWithInvalidString() {
        let config = SignedShotConfiguration(baseURLString: "not a valid url ://", publisherId: "pub-123")

        XCTAssertNil(config)
    }

    // MARK: - Sidecar Tests

    func testSidecarEncoding() throws {
        let sidecar = Sidecar(jwt: "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.test.sig")

        let encoder = JSONEncoder()
        let data = try encoder.encode(sidecar)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["version"] as? String, "1.0")

        let captureTrust = json?["capture_trust"] as? [String: Any]
        XCTAssertEqual(captureTrust?["jwt"] as? String, "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.test.sig")
    }

    func testSidecarDecoding() throws {
        let json = """
        {
            "version": "1.0",
            "capture_trust": {
                "jwt": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
            }
        }
        """

        let decoder = JSONDecoder()
        let sidecar = try decoder.decode(Sidecar.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(sidecar.version, "1.0")
        XCTAssertEqual(sidecar.captureTrust.jwt, "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature")
    }

    func testSidecarGenerator() throws {
        let generator = SidecarGenerator()
        let jwt = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.test.signature"

        let jsonString = try generator.generateString(jwt: jwt)

        XCTAssertTrue(jsonString.contains("\"version\" : \"1.0\""))
        XCTAssertTrue(jsonString.contains("\"capture_trust\""))
        XCTAssertTrue(jsonString.contains(jwt))
    }

    // MARK: - KeychainError Tests

    func testKeychainErrorDescriptions() {
        XCTAssertNotNil(KeychainError.encodingFailed.errorDescription)
        XCTAssertNotNil(KeychainError.saveFailed(-25299).errorDescription)
        XCTAssertNotNil(KeychainError.readFailed(-25300).errorDescription)
        XCTAssertNotNil(KeychainError.deleteFailed(-25301).errorDescription)
    }
}
