import Foundation

/// SignedShot SDK for iOS
/// Provides media authenticity verification through cryptographic signing and server-backed trust.
public enum SignedShotSDK {
    /// SDK version
    public static let version = "0.1.0"
}

// Re-export main types for convenience
// Users can import SignedShotSDK and access:
// - SignedShotClient: Main API client
// - SignedShotConfiguration: Client configuration
// - CaptureService: Camera capture functionality
// - CapturedPhoto: Captured photo with JPEG data
// - PhotoStorage: Save photos to Documents folder
// - KeychainStorage: Secure credential storage
