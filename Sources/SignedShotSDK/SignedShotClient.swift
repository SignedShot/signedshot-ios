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
    private static let externalIdKey = "external_id"

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

        let pubIdPrefix = String(configuration.publisherId.prefix(8))
        SignedShotLogger.api.info("Client initialized: \(configuration.baseURL), pub: \(pubIdPrefix)...")
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

    /// Get the stored external ID (or nil if not yet generated)
    public var externalId: String? {
        try? keychain.getString(forKey: Self.externalIdKey)
    }

    /// Register this device with the SignedShot backend
    /// - Parameter attestationToken: Optional attestation token (e.g., from Firebase App Check)
    /// - Returns: The registration response containing device info and token
    /// - Throws: SignedShotAPIError if registration fails
    @discardableResult
    public func registerDevice(attestationToken: String? = nil) async throws -> DeviceCreateResponse {
        let extId = try getOrCreateExternalId()
        return try await performRegistration(externalId: extId, attestationToken: attestationToken, isRetry: false)
    }

    /// Clear stored device credentials (for re-registration)
    public func clearStoredCredentials() throws {
        SignedShotLogger.keychain.info("Clearing all stored credentials")
        try keychain.delete(forKey: Self.deviceTokenKey)
        try keychain.delete(forKey: Self.deviceIdKey)
        try keychain.delete(forKey: Self.externalIdKey)
    }

    // MARK: - Private Registration Helpers

    private func getOrCreateExternalId() throws -> String {
        if let existing = try keychain.getString(forKey: Self.externalIdKey) {
            SignedShotLogger.keychain.debug("Using existing externalId: \(existing.prefix(8))...")
            return existing
        }

        let newId = UUID().uuidString
        try keychain.save(newId, forKey: Self.externalIdKey)
        SignedShotLogger.keychain.info("Generated new externalId: \(newId.prefix(8))...")
        return newId
    }

    private func performRegistration(
        externalId: String,
        attestationToken: String? = nil,
        isRetry: Bool
    ) async throws -> DeviceCreateResponse {
        SignedShotLogger.api.info("Registering device with externalId: \(externalId.prefix(8))...")

        let url = configuration.baseURL.appendingPathComponent("devices")
        SignedShotLogger.api.debug("POST \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publisherId, forHTTPHeaderField: "X-Publisher-ID")

        // Add attestation token header if provided
        if let token = attestationToken {
            request.setValue(token, forHTTPHeaderField: "X-Attestation-Token")
            SignedShotLogger.api.debug("Including attestation token in request")
        }

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
            let deviceIdPrefix = String(deviceResponse.deviceId.prefix(8))
            SignedShotLogger.api.info("Device registered: \(deviceIdPrefix)...")

            // Store token and device ID securely
            try keychain.save(deviceResponse.deviceToken, forKey: Self.deviceTokenKey)
            try keychain.save(deviceResponse.deviceId, forKey: Self.deviceIdKey)
            SignedShotLogger.keychain.info("Device credentials stored in Keychain")

            return deviceResponse

        case 400:
            SignedShotLogger.api.error("Registration failed: invalid publisher ID")
            throw SignedShotAPIError.invalidPublisherId

        case 409:
            // Device already registered on backend
            if isRetry {
                // Already retried once, give up
                SignedShotLogger.api.error("Registration failed: conflict persists after retry")
                throw SignedShotAPIError.deviceAlreadyRegistered
            }

            // Clear credentials and retry with new external_id
            SignedShotLogger.api.warning("Device conflict - clearing credentials and retrying")
            try clearStoredCredentials()
            let newExternalId = try getOrCreateExternalId()
            return try await performRegistration(
                externalId: newExternalId,
                attestationToken: attestationToken,
                isRetry: true
            )

        default:
            let errorMessage = try? decoder.decode(APIErrorResponse.self, from: data).detail
            let msg = errorMessage ?? "unknown"
            SignedShotLogger.api.error("Registration failed: \(httpResponse.statusCode) - \(msg)")
            throw SignedShotAPIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Capture Session

    /// Create a new capture session
    /// - Returns: Session info including capture_id, nonce, and expiration
    /// - Throws: SignedShotAPIError if session creation fails
    public func createCaptureSession() async throws -> CaptureSessionResponse {
        SignedShotLogger.api.info("Creating capture session...")

        guard isDeviceRegistered else {
            SignedShotLogger.api.error("Cannot create session: device not registered")
            throw SignedShotAPIError.deviceNotRegistered
        }

        let deviceToken = try getDeviceToken()
        let url = configuration.baseURL.appendingPathComponent("capture/session")
        SignedShotLogger.api.debug("POST \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            SignedShotLogger.api.error("Invalid response type")
            throw SignedShotAPIError.networkError(URLError(.badServerResponse))
        }

        SignedShotLogger.api.debug("Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 201:
            let sessionResponse = try decoder.decode(CaptureSessionResponse.self, from: data)
            let captureIdPrefix = String(sessionResponse.captureId.prefix(8))
            SignedShotLogger.api.info("Session created: \(captureIdPrefix)..., expires: \(sessionResponse.expiresAt)")
            return sessionResponse

        case 401:
            SignedShotLogger.api.error("Session creation failed: unauthorized")
            throw SignedShotAPIError.unauthorized

        default:
            let errorMessage = try? decoder.decode(APIErrorResponse.self, from: data).detail
            let msg = errorMessage ?? "unknown"
            SignedShotLogger.api.error("Session creation failed: \(httpResponse.statusCode) - \(msg)")
            throw SignedShotAPIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Trust Token

    /// Exchange a nonce for a signed trust token
    /// - Parameter nonce: The nonce received from createCaptureSession
    /// - Returns: The signed trust token (JWT)
    /// - Throws: SignedShotAPIError if exchange fails
    public func exchangeTrustToken(nonce: String) async throws -> TrustResponse {
        SignedShotLogger.api.info("Exchanging nonce for trust token...")

        guard isDeviceRegistered else {
            SignedShotLogger.api.error("Cannot exchange nonce: device not registered")
            throw SignedShotAPIError.deviceNotRegistered
        }

        let deviceToken = try getDeviceToken()
        let url = configuration.baseURL.appendingPathComponent("capture/trust")
        SignedShotLogger.api.debug("POST \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")

        let body = TrustRequest(nonce: nonce)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            SignedShotLogger.api.error("Invalid response type")
            throw SignedShotAPIError.networkError(URLError(.badServerResponse))
        }

        SignedShotLogger.api.debug("Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let trustResponse = try decoder.decode(TrustResponse.self, from: data)
            let tokenPrefix = String(trustResponse.trustToken.prefix(20))
            SignedShotLogger.api.info("Trust token received: \(tokenPrefix)...")
            return trustResponse

        case 400:
            SignedShotLogger.api.error("Trust exchange failed: invalid nonce")
            throw SignedShotAPIError.invalidNonce

        case 401:
            SignedShotLogger.api.error("Trust exchange failed: unauthorized")
            throw SignedShotAPIError.unauthorized

        case 410:
            SignedShotLogger.api.error("Trust exchange failed: session expired")
            throw SignedShotAPIError.sessionExpired

        default:
            let errorMessage = try? decoder.decode(APIErrorResponse.self, from: data).detail
            let msg = errorMessage ?? "unknown"
            SignedShotLogger.api.error("Trust exchange failed: \(httpResponse.statusCode) - \(msg)")
            throw SignedShotAPIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
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
