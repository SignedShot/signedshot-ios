# SignedShot iOS SDK

Capture photos with cryptographic proof of authenticity.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2016+-blue.svg)](https://developer.apple.com/ios/)

## Overview

SignedShot iOS SDK enables your app to capture photos with cryptographic proof that they haven't been altered since capture. It uses:

- **Secure Enclave** for tamper-proof key storage (P-256 ECDSA)
- **SHA-256 hashing** before any disk write
- **Firebase App Check** for device attestation (optional)

## Features

- Device registration with optional attestation
- Capture session management
- Content hashing and signing with Secure Enclave
- Sidecar JSON generation
- Keychain-based credential storage

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Device with Secure Enclave (iPhone 5s or later)

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SignedShot/signedshot-ios.git", from: "0.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → Enter the repository URL.

## Quick Start

### 1. Initialize the Client

```swift
import SignedShotSDK

let config = SignedShotConfiguration(
    baseURLString: "https://api.signedshot.io",
    publisherId: "your-publisher-id"
)!

let client = SignedShotClient(configuration: config)
```

### 2. Register the Device

```swift
// Register once per device
if !client.isDeviceRegistered {
    let response = try await client.registerDevice()
    print("Device registered: \(response.deviceId)")
}
```

### 3. Start a Capture Session

```swift
// Start session before capturing
let session = try await client.startSession()
// session.nonce - cryptographic nonce for this capture
// session.expiresAt - session expiration time
```

### 4. Capture and Sign

```swift
// After capturing the photo...
let integrityService = MediaIntegrityService(enclaveService: SecureEnclaveService())

// Sign the image data (hashes and signs with Secure Enclave)
let integrity = try await integrityService.sign(imageData: jpegData)

// Exchange nonce for trust token
let trustToken = try await client.exchangeNonce(session.nonce)

// Generate sidecar
let sidecar = SidecarGenerator().generate(
    captureId: session.captureId,
    trustToken: trustToken,
    mediaIntegrity: integrity
)

// Save photo and sidecar together
try jpegData.write(to: photoURL)
try sidecar.write(to: sidecarURL)
```

## Firebase App Check Integration

For production apps, enable device attestation with Firebase App Check:

### 1. Set Up Firebase

Add Firebase to your project and enable App Check in the Firebase Console.

### 2. Configure App Check Provider

```swift
import FirebaseCore
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Set up App Check before Firebase.configure()
        let providerFactory = MyAppCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)

        FirebaseApp.configure()
        return true
    }
}

class MyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
```

### 3. Pass Token During Registration

```swift
// Get App Check token
let appCheckToken = try await AppCheck.appCheck().token(forcingRefresh: false)

// Register with attestation
let response = try await client.registerDevice(attestationToken: appCheckToken.token)
```

### 4. Configure Publisher (Backend)

Your publisher must be configured with attestation on the backend:

```bash
curl -X PATCH https://api.signedshot.io/publishers/YOUR_PUBLISHER_ID \
  -H "Content-Type: application/json" \
  -d '{
    "sandbox": false,
    "attestation_provider": "firebase_app_check",
    "attestation_bundle_id": "com.yourcompany.yourapp"
  }'
```

## Example App

See the `ExampleApp/` directory for a complete implementation demonstrating:

- Camera capture with AVFoundation
- Secure Enclave key management
- Firebase App Check integration
- Sidecar generation and photo export

To run the example:

```bash
cd ExampleApp
open ExampleApp.xcodeproj
```

## Architecture

```
Sources/SignedShotSDK/
├── SignedShotClient.swift       # Main API client
├── CaptureService.swift         # Session management
├── SecureEnclaveService.swift   # Secure Enclave key operations
├── MediaIntegrityService.swift  # Hashing and signing
├── Sidecar.swift                # Sidecar JSON generation
├── KeychainStorage.swift        # Credential storage
└── APIModels.swift              # Request/response models
```

## Security

- **Private keys never leave the device** - Generated and stored in Secure Enclave
- **Keys are hardware-bound** - Cannot be extracted or copied
- **Content hashed before disk write** - Prevents tampering window
- **Attestation proves device legitimacy** - Firebase App Check verifies real devices

## Related Repositories

- [signedshot-api](https://github.com/SignedShot/signedshot-api) - Backend API
- [signedshot-validator](https://github.com/SignedShot/signedshot-validator) - Verification CLI/library

## Links

- [Website](https://signedshot.io)
- [Documentation](https://signedshot.io/docs)
- [Interactive Demo](https://signedshot.io/demo)

## License

MIT License - see [LICENSE](LICENSE) for details.
