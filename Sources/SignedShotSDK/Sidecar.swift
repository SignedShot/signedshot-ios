import Foundation

/// Sidecar file containing capture trust and media integrity information
public struct Sidecar: Codable, Sendable {
    /// Schema version
    public let version: String

    /// Capture trust information from the backend (ES256 signed JWT)
    public let captureTrust: CaptureTrust

    /// Media integrity proof from the device (optional, requires Secure Enclave)
    public let mediaIntegrity: MediaIntegrity?

    /// Initialize with JWT only (legacy, no media integrity)
    public init(version: String = "1.0", jwt: String) {
        self.version = version
        self.captureTrust = CaptureTrust(jwt: jwt)
        self.mediaIntegrity = nil
    }

    /// Initialize with JWT and media integrity
    public init(version: String = "1.0", jwt: String, mediaIntegrity: MediaIntegrity) {
        self.version = version
        self.captureTrust = CaptureTrust(jwt: jwt)
        self.mediaIntegrity = mediaIntegrity
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case captureTrust = "capture_trust"
        case mediaIntegrity = "media_integrity"
    }
}

/// Trust information from the SignedShot backend
public struct CaptureTrust: Codable, Sendable {
    /// ES256 signed JWT from the backend
    public let jwt: String

    public init(jwt: String) {
        self.jwt = jwt
    }
}

/// Generates sidecar files for captured photos
public struct SidecarGenerator {
    private let encoder: JSONEncoder

    public init() {
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Generate sidecar JSON data (legacy, no media integrity)
    /// - Parameter jwt: The trust token from the backend
    /// - Returns: JSON data for the sidecar file
    public func generate(jwt: String) throws -> Data {
        let sidecar = Sidecar(jwt: jwt)
        return try encoder.encode(sidecar)
    }

    /// Generate sidecar JSON data with media integrity
    /// - Parameters:
    ///   - jwt: The trust token from the backend
    ///   - mediaIntegrity: The media integrity proof from Secure Enclave
    /// - Returns: JSON data for the sidecar file
    public func generate(jwt: String, mediaIntegrity: MediaIntegrity) throws -> Data {
        let sidecar = Sidecar(jwt: jwt, mediaIntegrity: mediaIntegrity)
        return try encoder.encode(sidecar)
    }

    /// Generate sidecar and return as string (legacy, no media integrity)
    /// - Parameter jwt: The trust token from the backend
    /// - Returns: JSON string for the sidecar file
    public func generateString(jwt: String) throws -> String {
        let data = try generate(jwt: jwt)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SidecarError.encodingFailed
        }
        return string
    }

    /// Generate sidecar and return as string with media integrity
    /// - Parameters:
    ///   - jwt: The trust token from the backend
    ///   - mediaIntegrity: The media integrity proof from Secure Enclave
    /// - Returns: JSON string for the sidecar file
    public func generateString(jwt: String, mediaIntegrity: MediaIntegrity) throws -> String {
        let data = try generate(jwt: jwt, mediaIntegrity: mediaIntegrity)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SidecarError.encodingFailed
        }
        return string
    }
}

/// Errors that can occur during sidecar generation
public enum SidecarError: Error, LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode sidecar to JSON"
        }
    }
}
