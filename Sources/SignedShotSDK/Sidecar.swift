import Foundation

/// Sidecar file containing capture trust information
public struct Sidecar: Codable, Sendable {
    /// Schema version
    public let version: String

    /// Capture trust information from the backend
    public let captureTrust: CaptureTrust

    public init(version: String = "1.0", jwt: String) {
        self.version = version
        self.captureTrust = CaptureTrust(jwt: jwt)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case captureTrust = "capture_trust"
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

    /// Generate sidecar JSON data
    /// - Parameter jwt: The trust token from the backend
    /// - Returns: JSON data for the sidecar file
    public func generate(jwt: String) throws -> Data {
        let sidecar = Sidecar(jwt: jwt)
        return try encoder.encode(sidecar)
    }

    /// Generate sidecar and return as string
    /// - Parameter jwt: The trust token from the backend
    /// - Returns: JSON string for the sidecar file
    public func generateString(jwt: String) throws -> String {
        let data = try generate(jwt: jwt)
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
