import Foundation
import os.log

/// Configuration for the SignedShot client
public struct SignedShotConfiguration: Sendable {
    /// Base URL for the SignedShot API
    public let baseURL: URL

    /// Publisher ID for this app
    public let publisherId: String

    /// Create a configuration
    /// - Parameters:
    ///   - baseURL: Base URL for the SignedShot API (e.g., "https://api.signedshot.io")
    ///   - publisherId: Your publisher ID from SignedShot
    public init(baseURL: URL, publisherId: String) {
        self.baseURL = baseURL
        self.publisherId = publisherId
    }

    /// Create a configuration with a URL string
    /// - Parameters:
    ///   - baseURLString: Base URL string for the SignedShot API
    ///   - publisherId: Your publisher ID from SignedShot
    public init?(baseURLString: String, publisherId: String) {
        guard let url = URL(string: baseURLString) else {
            return nil
        }
        self.baseURL = url
        self.publisherId = publisherId
    }
}

/// Client for interacting with the SignedShot API
public actor SignedShotClient {
    // MARK: - Properties

    private let configuration: SignedShotConfiguration
    private let session: URLSession
    private let keychain: KeychainStorage
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Keychain keys
    private static let deviceTokenKey = "device_token"
    private static let deviceIdKey = "device_id"

    // MARK: - Initialization

    /// Create a new SignedShot client
    /// - Parameters:
    ///   - configuration: Client configuration
    ///   - keychain: Keychain storage (defaults to standard)
    public init(configuration: SignedShotConfiguration, keychain: KeychainStorage = KeychainStorage()) {
        self.configuration = configuration
        self.keychain = keychain
        self.session = URLSession.shared

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        SignedShotLogger.api.info("SignedShotClient initialized with baseURL: \(configuration.baseURL.absoluteString), publisherId: \(configuration.publisherId.prefix(8))...")
    }

    // MARK: - Device Registration

    /// Check if this device is already registered
    public var isDeviceRegistered: Bool {
        keychain.exists(forKey: Self.deviceTokenKey)
    }

    /// Get the stored device ID (if registered)
    public var deviceId: String? {
        try? keychain.getString(forKey: Self.deviceIdKey)
    }

    /// Register this device with the SignedShot backend
    /// - Parameter externalId: Unique identifier for this device (e.g., identifierForVendor)
    /// - Returns: The registration response containing device info and token
    /// - Throws: SignedShotAPIError if registration fails
    @discardableResult
    public func registerDevice(externalId: String) async throws -> DeviceCreateResponse {
        SignedShotLogger.api.info("Registering device with externalId: \(externalId.prefix(8))...")

        let url = configuration.baseURL.appendingPathComponent("devices")
        SignedShotLogger.api.debug("POST \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publisherId, forHTTPHeaderField: "X-Publisher-ID")

        let body = DeviceCreateRequest(externalId: externalId)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            SignedShotLogger.api.error("Invalid response type (not HTTPURLResponse)")
            throw SignedShotAPIError.networkError(URLError(.badServerResponse))
        }

        SignedShotLogger.api.debug("Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 201:
            let deviceResponse = try decoder.decode(DeviceCreateResponse.self, from: data)
            SignedShotLogger.api.info("Device registered successfully with deviceId: \(deviceResponse.deviceId.prefix(8))...")

            // Store token and device ID securely
            try keychain.save(deviceResponse.deviceToken, forKey: Self.deviceTokenKey)
            try keychain.save(deviceResponse.deviceId, forKey: Self.deviceIdKey)
            SignedShotLogger.keychain.info("Device credentials stored in Keychain")

            return deviceResponse

        case 400:
            SignedShotLogger.api.error("Registration failed: invalid publisher ID")
            throw SignedShotAPIError.invalidPublisherId

        case 409:
            SignedShotLogger.api.warning("Device already registered")
            throw SignedShotAPIError.deviceAlreadyRegistered

        default:
            let errorMessage = try? decoder.decode(APIErrorResponse.self, from: data).detail
            SignedShotLogger.api.error("Registration failed with status \(httpResponse.statusCode): \(errorMessage ?? "unknown")")
            throw SignedShotAPIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    /// Clear stored device credentials (for re-registration)
    public func clearStoredCredentials() throws {
        try keychain.delete(forKey: Self.deviceTokenKey)
        try keychain.delete(forKey: Self.deviceIdKey)
    }

    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SignedShotAPIError.networkError(error)
        }
    }

    /// Get the stored device token for authenticated requests
    func getDeviceToken() throws -> String {
        guard let token = try keychain.getString(forKey: Self.deviceTokenKey) else {
            throw SignedShotAPIError.unauthorized
        }
        return token
    }
}
