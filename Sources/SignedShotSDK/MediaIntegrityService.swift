import CryptoKit
import Foundation

/// Result of media integrity signing
public struct MediaIntegrity: Codable, Sendable {
    /// SHA-256 hash of the media content (hex string, 64 characters)
    public let contentHash: String

    /// Base64-encoded ECDSA signature of the signed message
    public let signature: String

    /// Base64-encoded public key (uncompressed EC point, 65 bytes)
    public let publicKey: String

    /// UUID of the capture session
    public let captureId: String

    /// ISO8601 UTC timestamp of when the media was captured
    public let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case signature
        case publicKey = "public_key"
        case captureId = "capture_id"
        case capturedAt = "captured_at"
    }
}

/// Service for generating media integrity proofs
///
/// This service computes a SHA-256 hash of media content and signs it
/// using the device's Secure Enclave, creating a cryptographic proof
/// that the content was captured on this device.
///
/// Usage:
/// ```swift
/// let enclave = SecureEnclaveService()
/// let integrityService = MediaIntegrityService(enclaveService: enclave)
///
/// let integrity = try integrityService.generateIntegrity(
///     for: jpegData,
///     captureId: "uuid-string",
///     capturedAt: Date()
/// )
/// ```
public final class MediaIntegrityService: Sendable {
    private let enclaveService: SecureEnclaveService

    /// ISO8601 formatter for capturedAt timestamps (UTC, no fractional seconds)
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Initialize with a Secure Enclave service
    /// - Parameter enclaveService: The Secure Enclave service for signing
    public init(enclaveService: SecureEnclaveService = SecureEnclaveService()) {
        self.enclaveService = enclaveService
    }

    // MARK: - Public Methods

    /// Generate a media integrity proof for the given content
    ///
    /// This method:
    /// 1. Computes SHA-256 hash of the content
    /// 2. Formats the capture timestamp as ISO8601 UTC
    /// 3. Builds the signed message: `{hash}:{captureId}:{capturedAt}`
    /// 4. Signs the message with the Secure Enclave
    /// 5. Returns all components needed for verification
    ///
    /// - Parameters:
    ///   - data: The media content (e.g., JPEG bytes)
    ///   - captureId: UUID of the capture session (from backend)
    ///   - capturedAt: Timestamp when the media was captured
    /// - Returns: MediaIntegrity containing hash, signature, and metadata
    /// - Throws: `MediaIntegrityError` or `SecureEnclaveError` if signing fails
    public func generateIntegrity(
        for data: Data,
        captureId: String,
        capturedAt: Date
    ) throws -> MediaIntegrity {
        // 1. Compute SHA-256 hash
        let contentHash = computeHash(for: data)

        // 2. Format timestamp as ISO8601 UTC
        let capturedAtString = Self.iso8601Formatter.string(from: capturedAt)

        // 3. Build signed message
        let message = buildMessage(
            contentHash: contentHash,
            captureId: captureId,
            capturedAt: capturedAtString
        )

        // 4. Sign with Secure Enclave
        let signature = try enclaveService.signBase64(data: Data(message.utf8))

        // 5. Get public key for verification
        let publicKey = try enclaveService.getPublicKeyBase64()

        return MediaIntegrity(
            contentHash: contentHash,
            signature: signature,
            publicKey: publicKey,
            captureId: captureId,
            capturedAt: capturedAtString
        )
    }

    /// Generate integrity using a UUID for captureId
    /// - Parameters:
    ///   - data: The media content
    ///   - captureId: UUID of the capture session
    ///   - capturedAt: Timestamp when captured
    /// - Returns: MediaIntegrity proof
    public func generateIntegrity(
        for data: Data,
        captureId: UUID,
        capturedAt: Date
    ) throws -> MediaIntegrity {
        try generateIntegrity(
            for: data,
            captureId: captureId.uuidString,
            capturedAt: capturedAt
        )
    }

    // MARK: - Hash Computation

    /// Compute SHA-256 hash of data and return as lowercase hex string
    /// - Parameter data: The data to hash
    /// - Returns: 64-character lowercase hex string
    public func computeHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Message Building

    /// Build the message to be signed
    ///
    /// Format: `{contentHash}:{captureId}:{capturedAt}`
    ///
    /// - Parameters:
    ///   - contentHash: SHA-256 hex hash
    ///   - captureId: Capture session UUID
    ///   - capturedAt: ISO8601 timestamp
    /// - Returns: The message string to sign
    public func buildMessage(
        contentHash: String,
        captureId: String,
        capturedAt: String
    ) -> String {
        "\(contentHash):\(captureId):\(capturedAt)"
    }

    // MARK: - Verification (for testing)

    /// Verify a media integrity proof
    ///
    /// This checks that the signature is valid for the reconstructed message.
    /// Useful for testing; in production, verification happens on the validator.
    ///
    /// - Parameters:
    ///   - integrity: The media integrity proof to verify
    ///   - data: The original media content
    /// - Returns: True if the signature is valid
    public func verify(integrity: MediaIntegrity, for data: Data) throws -> Bool {
        // Recompute hash
        let computedHash = computeHash(for: data)
        guard computedHash == integrity.contentHash else {
            return false
        }

        // Rebuild message
        let message = buildMessage(
            contentHash: integrity.contentHash,
            captureId: integrity.captureId,
            capturedAt: integrity.capturedAt
        )

        // Decode signature
        guard let signatureData = Data(base64Encoded: integrity.signature) else {
            return false
        }

        // Verify with Secure Enclave
        return try enclaveService.verify(
            signature: signatureData,
            for: Data(message.utf8)
        )
    }
}

// MARK: - Media Integrity Errors

public enum MediaIntegrityError: Error, LocalizedError {
    case hashMismatch
    case invalidSignature

    public var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "Content hash does not match the media data"
        case .invalidSignature:
            return "Signature is invalid or corrupted"
        }
    }
}
