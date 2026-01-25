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

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .deviceAlreadyRegistered:
            return "Device is already registered"
        case .invalidPublisherId:
            return "Invalid publisher ID format"
        case .unauthorized:
            return "Unauthorized - invalid or expired token"
        case .notFound:
            return "Resource not found"
        }
    }
}

// MARK: - API Error Response

/// Standard error response from the API
struct APIErrorResponse: Codable {
    let detail: String?
}
