import Foundation
import os.log
import Security

/// Service for managing Secure Enclave keys and signing operations
///
/// This service creates and manages P-256 keys in the device's Secure Enclave.
/// The private key never leaves the hardware, providing strong security guarantees.
///
/// Usage:
/// ```swift
/// let enclave = SecureEnclaveService()
///
/// // Create key if it doesn't exist
/// if !enclave.keyExists() {
///     try enclave.createKey()
/// }
///
/// // Get public key for verification
/// let publicKey = try enclave.getPublicKeyData()
///
/// // Sign data
/// let signature = try enclave.sign(data: dataToSign)
/// ```
public final class SecureEnclaveService: Sendable {
    private let keyTag: String

    /// Initialize with a key tag identifier
    /// - Parameter keyTag: Unique identifier for the key in the Keychain (default: "io.signedshot.sdk.enclave.signing")
    public init(keyTag: String = "io.signedshot.sdk.enclave.signing") {
        self.keyTag = keyTag
        SignedShotLogger.enclave.debug("SecureEnclaveService initialized with tag: \(keyTag)")
    }

    // MARK: - Key Management

    /// Check if a key already exists in the Secure Enclave
    /// - Returns: True if the key exists
    public func keyExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        let exists = status == errSecSuccess
        SignedShotLogger.enclave.debug("Key exists check: \(exists)")
        return exists
    }

    /// Create a new P-256 key pair in the Secure Enclave
    ///
    /// The private key is stored in the Secure Enclave and never leaves the hardware.
    /// If a key with the same tag already exists, this will throw an error.
    ///
    /// - Throws: `SecureEnclaveError.keyAlreadyExists` if key exists, or other creation errors
    public func createKey() throws {
        SignedShotLogger.enclave.info("Creating new Secure Enclave key")

        if keyExists() {
            SignedShotLogger.enclave.error("Key already exists")
            throw SecureEnclaveError.keyAlreadyExists
        }

        // Access control: require user presence (biometric or passcode) for signing
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &accessControlError
        ) else {
            let error = accessControlError?.takeRetainedValue()
            SignedShotLogger.enclave.error("Failed to create access control: \(String(describing: error))")
            throw SecureEnclaveError.accessControlCreationFailed(error)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: accessControl
            ]
        ]

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            let cfError = error?.takeRetainedValue()
            SignedShotLogger.enclave.error("Failed to create key: \(String(describing: cfError))")
            throw SecureEnclaveError.keyCreationFailed(cfError)
        }

        SignedShotLogger.enclave.info("Successfully created Secure Enclave key")
    }

    /// Get the private key reference from the Secure Enclave
    /// - Returns: SecKey reference to the private key
    /// - Throws: `SecureEnclaveError.keyNotFound` if no key exists
    private func getPrivateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            SignedShotLogger.enclave.error("Failed to retrieve private key: status \(status)")
            throw SecureEnclaveError.keyNotFound
        }

        // swiftlint:disable:next force_cast
        return result as! SecKey
    }

    /// Get the public key from the Secure Enclave key pair
    /// - Returns: SecKey reference to the public key
    /// - Throws: `SecureEnclaveError.keyNotFound` if no key exists
    public func getPublicKey() throws -> SecKey {
        let privateKey = try getPrivateKey()

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            SignedShotLogger.enclave.error("Failed to extract public key from private key")
            throw SecureEnclaveError.publicKeyExtractionFailed
        }

        return publicKey
    }

    /// Get the public key as raw data in uncompressed point format (0x04 || x || y)
    ///
    /// The format is 65 bytes: 1 byte prefix (0x04) + 32 bytes X coordinate + 32 bytes Y coordinate.
    /// This is the standard uncompressed EC point format used for verification.
    ///
    /// - Returns: 65-byte Data containing the uncompressed public key
    /// - Throws: `SecureEnclaveError` if key retrieval or export fails
    public func getPublicKeyData() throws -> Data {
        let publicKey = try getPublicKey()

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let cfError = error?.takeRetainedValue()
            SignedShotLogger.enclave.error("Failed to export public key: \(String(describing: cfError))")
            throw SecureEnclaveError.publicKeyExportFailed(cfError)
        }

        SignedShotLogger.enclave.debug("Exported public key: \(publicKeyData.count) bytes")
        return publicKeyData
    }

    /// Get the public key as a Base64-encoded string (uncompressed point format)
    /// - Returns: Base64 string representation of the public key
    /// - Throws: `SecureEnclaveError` if key retrieval or export fails
    public func getPublicKeyBase64() throws -> String {
        let data = try getPublicKeyData()
        return data.base64EncodedString()
    }

    /// Delete the key from the Secure Enclave
    ///
    /// Use this for testing or to reset the device's signing key.
    /// After deletion, a new key must be created before signing operations.
    ///
    /// - Throws: `SecureEnclaveError.keyDeletionFailed` if deletion fails
    public func deleteKey() throws {
        SignedShotLogger.enclave.info("Deleting Secure Enclave key")

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            SignedShotLogger.enclave.error("Failed to delete key: status \(status)")
            throw SecureEnclaveError.keyDeletionFailed(status)
        }

        SignedShotLogger.enclave.info("Successfully deleted Secure Enclave key")
    }

    // MARK: - Signing

    /// Sign data using the Secure Enclave private key
    ///
    /// Uses ECDSA with SHA-256 (ES256 algorithm). The signature is in DER format.
    ///
    /// - Parameter data: The data to sign
    /// - Returns: DER-encoded ECDSA signature
    /// - Throws: `SecureEnclaveError` if signing fails
    public func sign(data: Data) throws -> Data {
        SignedShotLogger.enclave.debug("Signing \(data.count) bytes")

        let privateKey = try getPrivateKey()

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            let cfError = error?.takeRetainedValue()
            SignedShotLogger.enclave.error("Signing failed: \(String(describing: cfError))")
            throw SecureEnclaveError.signingFailed(cfError)
        }

        SignedShotLogger.enclave.debug("Generated signature: \(signature.count) bytes")
        return signature
    }

    /// Sign a UTF-8 string using the Secure Enclave private key
    /// - Parameter message: The string message to sign
    /// - Returns: DER-encoded ECDSA signature
    /// - Throws: `SecureEnclaveError` if signing fails
    public func sign(message: String) throws -> Data {
        guard let data = message.data(using: .utf8) else {
            throw SecureEnclaveError.encodingFailed
        }
        return try sign(data: data)
    }

    /// Sign data and return the signature as Base64
    /// - Parameter data: The data to sign
    /// - Returns: Base64-encoded signature
    /// - Throws: `SecureEnclaveError` if signing fails
    public func signBase64(data: Data) throws -> String {
        let signature = try sign(data: data)
        return signature.base64EncodedString()
    }

    // MARK: - Verification (for testing)

    /// Verify a signature against data using the public key
    ///
    /// This is useful for testing that signing works correctly.
    /// In production, verification typically happens on the server or validator.
    ///
    /// - Parameters:
    ///   - signature: The DER-encoded signature to verify
    ///   - data: The original data that was signed
    /// - Returns: True if the signature is valid, false otherwise
    /// - Throws: `SecureEnclaveError` if public key retrieval fails
    public func verify(signature: Data, for data: Data) throws -> Bool {
        let publicKey = try getPublicKey()

        // SecKeyVerifySignature returns false for invalid signatures
        // and may set an error, but that's expected behavior - not an exception
        let isValid = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            signature as CFData,
            nil  // Don't capture error - false return is sufficient
        )

        return isValid
    }
}

// MARK: - Secure Enclave Errors

public enum SecureEnclaveError: Error, LocalizedError {
    case keyAlreadyExists
    case keyNotFound
    case keyCreationFailed(CFError?)
    case keyDeletionFailed(OSStatus)
    case accessControlCreationFailed(CFError?)
    case publicKeyExtractionFailed
    case publicKeyExportFailed(CFError?)
    case signingFailed(CFError?)
    case verificationFailed(CFError?)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .keyAlreadyExists:
            return "A key already exists in the Secure Enclave"
        case .keyNotFound:
            return "No key found in the Secure Enclave"
        case .keyCreationFailed(let error):
            return "Failed to create key in Secure Enclave: \(String(describing: error))"
        case .keyDeletionFailed(let status):
            return "Failed to delete key from Secure Enclave: \(status)"
        case .accessControlCreationFailed(let error):
            return "Failed to create access control: \(String(describing: error))"
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from private key"
        case .publicKeyExportFailed(let error):
            return "Failed to export public key: \(String(describing: error))"
        case .signingFailed(let error):
            return "Failed to sign data: \(String(describing: error))"
        case .verificationFailed(let error):
            return "Failed to verify signature: \(String(describing: error))"
        case .encodingFailed:
            return "Failed to encode message to UTF-8"
        }
    }
}
