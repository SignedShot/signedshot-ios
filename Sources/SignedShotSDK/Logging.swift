import Foundation
import os.log

/// Centralized logging for the SignedShot SDK
enum SignedShotLogger {
    private static let subsystem = "io.signedshot.sdk"

    static let api = Logger(subsystem: subsystem, category: "API")
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    static let capture = Logger(subsystem: subsystem, category: "Capture")
    static let general = Logger(subsystem: subsystem, category: "General")
}
