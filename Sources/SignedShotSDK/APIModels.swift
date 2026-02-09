import Foundation

// MARK: - Device Registration

/// Request to register a new device
public struct DeviceCreateRequest: Codable, Sendable {
    /// Unique identifier for the device (e.g., hardware ID, app installation ID)
    public let externalId: String

    public init(externalId: String) {
        self.externalId = externalId
    }

    private enum CodingKeys: String, CodingKey {
        case externalId = "external_id"
    }
}

/// Response after successful device registration
public struct DeviceCreateResponse: Codable, Sendable {
    /// Internal UUID for the device
    public let deviceId: String

    /// UUID of the publisher this device belongs to
    public let publisherId: String

    /// The external ID provided during registration
    public let externalId: String

    /// Bearer token for authenticating capture requests. Store securely - only returned once.
    public let deviceToken: String

    /// When the device was registered
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case publisherId = "publisher_id"
        case externalId = "external_id"
        case deviceToken = "device_token"
        case createdAt = "created_at"
    }
}

// MARK: - Capture Session

/// Response after creating a capture session
public struct CaptureSessionResponse: Codable, Sendable {
    /// Unique identifier for this capture
    public let captureId: String

    /// One-time token to exchange for a trust token after capture
    public let nonce: String

    /// When this session expires (must complete capture before this time)
    public let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case nonce
        case expiresAt = "expires_at"
    }
}

/// Request to generate a trust token
public struct TrustRequest: Codable, Sendable {
    /// The nonce received from the capture session
    public let nonce: String

    public init(nonce: String) {
        self.nonce = nonce
    }
}

/// Response with the signed trust token
public struct TrustResponse: Codable, Sendable {
    /// Signed JWT containing capture proof. Embed this in your media metadata.
    public let trustToken: String

    private enum CodingKeys: String, CodingKey {
        case trustToken = "trust_token"
    }
}

// MARK: - API Errors

/// Errors that can occur during API operations
public enum SignedShotAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case deviceAlreadyRegistered
    case invalidPublisherId
    case unauthorized
    case notFound
    case deviceNotRegistered
    case invalidNonce
    case sessionExpired

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to connect to the server. Please try again later."
        case .networkError:
            return "No internet connection. Check your network and try again."
        case .httpError(let statusCode, _):
            if statusCode >= 500 {
                return "The server is temporarily unavailable. Please try again later."
            }
            return "Something went wrong. Please try again."
        case .decodingError:
            return "Received an unexpected response from the server. Please try again."
        case .deviceAlreadyRegistered:
            return "This device is already registered."
        case .invalidPublisherId:
            return "Configuration error. Please reinstall the app."
        case .unauthorized:
            return "Your device session has expired. Please register again."
        case .notFound:
            return "The requested resource was not found."
        case .deviceNotRegistered:
            return "Please register your device first."
        case .invalidNonce:
            return "This capture session has already been used. Please start a new session."
        case .sessionExpired:
            return "Your capture session has expired. Please start a new one."
        }
    }
}

// MARK: - API Error Response

/// Standard error response from the API
struct APIErrorResponse: Codable {
    let detail: String?
}
