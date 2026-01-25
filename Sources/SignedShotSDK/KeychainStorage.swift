import Foundation
import os.log
import Security

/// Secure storage for sensitive data using the iOS Keychain
public final class KeychainStorage: Sendable {
    private let service: String

    /// Initialize with a service identifier
    /// - Parameter service: Unique identifier for this app's keychain items
    public init(service: String = "io.signedshot.sdk") {
        self.service = service
        SignedShotLogger.keychain.debug("KeychainStorage initialized with service: \(service)")
    }

    // MARK: - Public Methods

    /// Save a string value to the keychain
    /// - Parameters:
    ///   - value: The string to store
    ///   - key: The key to store it under
    public func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, forKey: key)
    }

    /// Save data to the keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The key to store it under
    public func save(_ data: Data, forKey key: String) throws {
        SignedShotLogger.keychain.debug("Saving \(data.count) bytes to keychain for key: \(key)")

        // Delete any existing item first
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            SignedShotLogger.keychain.error("Failed to save to keychain: status \(status)")
            throw KeychainError.saveFailed(status)
        }

        SignedShotLogger.keychain.debug("Successfully saved to keychain for key: \(key)")
    }

    /// Retrieve a string value from the keychain
    /// - Parameter key: The key to look up
    /// - Returns: The stored string, or nil if not found
    public func getString(forKey key: String) throws -> String? {
        guard let data = try getData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve data from the keychain
    /// - Parameter key: The key to look up
    /// - Returns: The stored data, or nil if not found
    public func getData(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status)
        }
    }

    /// Delete an item from the keychain
    /// - Parameter key: The key to delete
    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a key exists in the keychain
    /// - Parameter key: The key to check
    /// - Returns: True if the key exists
    public func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - Keychain Errors

public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode string to data"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}
