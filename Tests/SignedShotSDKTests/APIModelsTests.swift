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

    // MARK: - SignedShotAPIError Tests

    func testAPIErrorDescriptions() {
        XCTAssertNotNil(SignedShotAPIError.invalidURL.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.networkError(URLError(.notConnectedToInternet)).errorDescription)
        XCTAssertNotNil(SignedShotAPIError.httpError(statusCode: 500, message: "Server error").errorDescription)
        XCTAssertNotNil(SignedShotAPIError.httpError(statusCode: 500, message: nil).errorDescription)
        XCTAssertNotNil(SignedShotAPIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))).errorDescription)
        XCTAssertNotNil(SignedShotAPIError.deviceAlreadyRegistered.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.invalidPublisherId.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.unauthorized.errorDescription)
        XCTAssertNotNil(SignedShotAPIError.notFound.errorDescription)
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

    // MARK: - KeychainError Tests

    func testKeychainErrorDescriptions() {
        XCTAssertNotNil(KeychainError.encodingFailed.errorDescription)
        XCTAssertNotNil(KeychainError.saveFailed(-25299).errorDescription)
        XCTAssertNotNil(KeychainError.readFailed(-25300).errorDescription)
        XCTAssertNotNil(KeychainError.deleteFailed(-25301).errorDescription)
    }
}
