//
//  ContentView.swift
//  ExampleApp
//

import Combine
import FirebaseAppCheck
import os.log
import SignedShotSDK
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "io.signedshot.capture", category: "App")

struct ContentView: View {
    @StateObject private var captureService = CaptureService()
    @State private var lastCapturedPhoto: CapturedPhoto?
    @State private var errorMessage: String?
    @State private var savedPhotoURL: URL?
    @State private var isSetup = false

    // Registration state
    @State private var isDeviceRegistered = false
    @State private var isRegistering = false
    @State private var deviceId: String?

    // Session state
    @State private var currentSession: CaptureSessionResponse?
    @State private var isStartingSession = false

    // Trust token state
    @State private var trustToken: String?
    @State private var isExchangingToken = false
    @State private var sidecarURL: URL?

    private let sidecarGenerator = SidecarGenerator()
    private let enclaveService = SecureEnclaveService()
    private let integrityService: MediaIntegrityService

    private let storage = PhotoStorage()
    private let client: SignedShotClient

    // Session expired state
    @State private var sessionExpired = false
    @State private var sessionTimeRemaining: Int = 0

    // Secure Enclave state
    @State private var isEnclaveReady = false

    // Secure Enclave test state
    @State private var isTestingEnclave = false
    @State private var enclaveTestResult: String?
    @State private var showEnclaveTest = false

    init() {
        // Configure the SignedShot client based on build configuration
        #if DEBUG
        let config = SignedShotConfiguration(
            baseURLString: "https://dev-api.signedshot.io",
            publisherId: "9a5b1062-a8fe-4871-bdc1-fe54e96cbf1c"
        )!
        #else
        let config = SignedShotConfiguration(
            baseURLString: "https://api.signedshot.io",
            publisherId: "8f6b5d94-af3b-4f57-be68-e93eedd772fc"
        )!
        #endif
        client = SignedShotClient(configuration: config)
        integrityService = MediaIntegrityService(enclaveService: enclaveService)
    }

    private var hasActiveSession: Bool {
        guard let session = currentSession else { return false }
        return session.expiresAt > Date()
    }

    var body: some View {
        ZStack {
            // Camera preview
            if isSetup {
                CameraPreviewView(previewLayer: captureService.getPreviewLayer())
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // UI overlay
            VStack {
                // Status bar
                statusBar
                    .padding()

                Spacer()

                // Registration prompt (if not registered)
                if !isDeviceRegistered {
                    registrationPrompt
                        .padding()
                }

                // Session prompt (if registered but no active session)
                if isDeviceRegistered && !hasActiveSession {
                    sessionPrompt
                        .padding()
                }

                // Session info (if active session)
                if let session = currentSession, hasActiveSession {
                    sessionInfo(session)
                        .padding()
                }

                // Captured photo preview
                if let photo = lastCapturedPhoto {
                    capturedPhotoPreview(photo)
                        .padding()
                }

                // Capture button
                captureButton
                    .padding(.bottom, 40)
            }
        }
        .task {
            await initialize()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if let session = currentSession {
                let remaining = Int(session.expiresAt.timeIntervalSinceNow)
                sessionTimeRemaining = max(remaining, 0)
                if remaining <= 0 {
                    sessionExpired = true
                    currentSession = nil
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showEnclaveTest) {
            enclaveTestSheet
        }
    }

    private var enclaveTestSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if isTestingEnclave {
                    HStack {
                        ProgressView()
                        Text("Testing Secure Enclave...")
                            .padding(.leading, 8)
                    }
                    .padding()
                } else if let result = enclaveTestResult {
                    ScrollView {
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                }
                Spacer()
            }
            .navigationTitle("Secure Enclave Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showEnclaveTest = false
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack {
            Text("SignedShot")
                .font(.headline)
                .foregroundColor(.white)

            // Secure Enclave test button (debug only)
            #if DEBUG
            Button(action: {
                showEnclaveTest = true
                Task { await testSecureEnclave() }
            }) {
                Image(systemName: "key.fill")
                    .foregroundColor(.yellow)
            }
            #endif

            Spacer()

            // Registration status indicator (long press to reset)
            if isDeviceRegistered {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    if let deviceId = deviceId {
                        Text(String(deviceId.prefix(8)))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await resetDevice() }
                    } label: {
                        Label("Reset Device", systemImage: "trash")
                    }
                }
            } else {
                Image(systemName: "shield.slash")
                    .foregroundColor(.orange)
            }

            // Session status indicator
            if hasActiveSession {
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
            }

            // Camera status
            if captureService.isSessionRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
        .cornerRadius(8)
    }

    private var registrationPrompt: some View {
        VStack(spacing: 12) {
            Text("Device Not Registered")
                .font(.headline)
                .foregroundColor(.white)

            Text("Register this device to enable authenticated captures")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await registerDevice() }
            }) {
                HStack {
                    if isRegistering {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "shield.checkered")
                    }
                    Text(isRegistering ? "Registering..." : "Register Device")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.blue)
                .cornerRadius(8)
            }
            .disabled(isRegistering)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(12)
    }

    private var sessionPrompt: some View {
        VStack(spacing: 12) {
            if sessionExpired {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.title2)

                Text("Session Expired")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Your capture session has expired. Create a new one to continue.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            } else {
                Text("Ready to Capture")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Start a capture session to take an authenticated photo")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task { await startSession() }
            }) {
                HStack {
                    if isStartingSession {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                    Text(isStartingSession ? "Starting..." : sessionExpired ? "Create New Session" : "Start Session")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(sessionExpired ? .orange : .green)
                .cornerRadius(8)
            }
            .disabled(isStartingSession)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(12)
    }

    private func sessionInfo(_ session: CaptureSessionResponse) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Session Active")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text("ID: \(String(session.captureId.prefix(8)))...")
                .font(.caption2)
                .foregroundColor(.gray)

            if sessionTimeRemaining > 0 {
                Text("Expires in \(sessionTimeRemaining)s")
                    .font(.caption2)
                    .foregroundColor(sessionTimeRemaining < 30 ? .orange : .gray)
            }
        }
        .padding(8)
        .background(.black.opacity(0.7))
        .cornerRadius(8)
    }

    private func capturedPhotoPreview(_ photo: CapturedPhoto) -> some View {
        VStack(spacing: 8) {
            if let uiImage = UIImage(data: photo.jpegData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 150)
                    .cornerRadius(8)
            }

            VStack(spacing: 4) {
                if let url = savedPhotoURL {
                    Text("\(url.lastPathComponent)")
                        .fontWeight(.medium)
                }
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(photo.jpegData.count),
                    countStyle: .file
                ))
            }
            .font(.caption)
            .foregroundColor(.white)

            // Trust token status
            if isExchangingToken {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Getting trust token...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if let token = trustToken {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Trust Token Received")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    Text(String(token.prefix(40)) + "...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(2)

                    if let sidecarURL = sidecarURL {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundColor(.blue)
                            Text(sidecarURL.lastPathComponent)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            Button("Dismiss") {
                lastCapturedPhoto = nil
                savedPhotoURL = nil
                trustToken = nil
                sidecarURL = nil
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.top, 4)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(12)
    }

    private var captureButton: some View {
        Button(action: {
            Task { await capturePhoto() }
        }) {
            ZStack {
                Circle()
                    .fill(hasActiveSession ? .white : .gray)
                    .frame(width: 70, height: 70)

                Circle()
                    .stroke(hasActiveSession ? .white : .gray, lineWidth: 4)
                    .frame(width: 80, height: 80)

                if captureService.isCaptureInProgress {
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .disabled(!canCapture)
    }

    private var canCapture: Bool {
        isSetup && hasActiveSession && isEnclaveReady && !captureService.isCaptureInProgress
    }

    // MARK: - Actions

    private func initialize() async {
        // Check registration status
        isDeviceRegistered = await client.isDeviceRegistered
        deviceId = await client.deviceId

        // Setup Secure Enclave key
        await setupSecureEnclave()

        // Setup camera
        await setupCamera()
    }

    private func setupSecureEnclave() async {
        do {
            if !enclaveService.keyExists() {
                try enclaveService.createKey()
            }
            isEnclaveReady = true
        } catch {
            // Secure Enclave not available (simulator) - continue without it
            isEnclaveReady = false
            logger.warning("Secure Enclave not available: \(error.localizedDescription)")
        }
    }

    private func setupCamera() async {
        do {
            try await captureService.setupSession()
            captureService.startSession()
            isSetup = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func registerDevice() async {
        isRegistering = true
        defer { isRegistering = false }

        do {
            // Get Firebase App Check token for attestation
            let attestationToken = try await getAppCheckToken()

            // Registration handles external_id internally
            // If 409 conflict occurs, it auto-retries with a new ID
            let response = try await client.registerDevice(attestationToken: attestationToken)

            isDeviceRegistered = true
            deviceId = response.deviceId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDevice() async {
        do {
            try await client.clearStoredCredentials()
            isDeviceRegistered = false
            deviceId = nil
            currentSession = nil
            trustToken = nil
            logger.info("Device credentials cleared successfully")
        } catch {
            errorMessage = "Failed to reset: \(error.localizedDescription)"
            logger.error("Failed to clear device credentials: \(error.localizedDescription)")
        }
    }

    /// Get Firebase App Check token for device attestation
    private func getAppCheckToken() async throws -> String? {
        do {
            let token = try await AppCheck.appCheck().token(forcingRefresh: false)
            return token.token
        } catch {
            // Log but don't fail - let the backend decide if token is required
            logger.warning("App Check token retrieval failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func startSession() async {
        isStartingSession = true
        defer { isStartingSession = false }

        do {
            let session = try await client.createCaptureSession()
            currentSession = session
            sessionExpired = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capturePhoto() async {
        guard let session = currentSession, hasActiveSession else {
            errorMessage = "No active session"
            return
        }

        guard isEnclaveReady else {
            errorMessage = "Secure Enclave not available. Cannot capture without media integrity."
            return
        }

        do {
            // 1. Capture photo → JPEG bytes in memory
            let photo = try await captureService.capturePhoto()
            lastCapturedPhoto = photo
            let capturedAt = photo.capturedAt

            // 2. Generate media integrity (hash + sign) BEFORE saving to disk
            let mediaIntegrity = try integrityService.generateIntegrity(
                for: photo.jpegData,
                captureId: session.captureId,
                capturedAt: capturedAt
            )

            // 3. Exchange nonce for trust token
            isExchangingToken = true
            let response = try await client.exchangeTrustToken(nonce: session.nonce)
            trustToken = response.trustToken
            isExchangingToken = false

            // 4. Generate sidecar (JWT + media_integrity)
            let sidecarData = try sidecarGenerator.generate(
                jwt: response.trustToken,
                mediaIntegrity: mediaIntegrity
            )

            // 5. Save photo + sidecar together
            let url = try storage.save(photo)
            savedPhotoURL = url
            sidecarURL = try storage.saveSidecar(sidecarData, for: url)

            // Clear session after successful exchange (one-time use)
            currentSession = nil
        } catch SignedShotAPIError.sessionExpired {
            isExchangingToken = false
            currentSession = nil
            sessionExpired = true
            lastCapturedPhoto = nil
        } catch {
            isExchangingToken = false
            errorMessage = error.localizedDescription
        }
    }

    private func testSecureEnclave() async {
        isTestingEnclave = true
        enclaveTestResult = nil

        var results: [String] = []
        results.append("=== Secure Enclave Test ===\n")

        do {
            // Check if key exists
            let keyExists = enclaveService.keyExists()
            results.append("1. Key exists: \(keyExists ? "YES" : "NO")")

            // Create key if needed
            if !keyExists {
                try enclaveService.createKey()
                results.append("2. Key created: SUCCESS")
            } else {
                results.append("2. Key creation: SKIPPED (already exists)")
            }

            // Get public key
            let publicKeyData = try enclaveService.getPublicKeyData()
            results.append("3. Public key size: \(publicKeyData.count) bytes")
            results.append("   Format: 0x\(String(format: "%02X", publicKeyData[0])) (uncompressed)")

            let publicKeyBase64 = try enclaveService.getPublicKeyBase64()
            results.append("4. Public key (base64):")
            results.append("   \(publicKeyBase64.prefix(44))...")

            // Sign test message
            let testMessage = "Hello, SignedShot!"
            let signature = try enclaveService.sign(message: testMessage)
            results.append("5. Signature size: \(signature.count) bytes")

            let signatureBase64 = signature.base64EncodedString()
            results.append("6. Signature (base64):")
            results.append("   \(signatureBase64.prefix(44))...")

            // Verify signature
            let messageData = Data(testMessage.utf8)
            let isValid = try enclaveService.verify(signature: signature, for: messageData)
            results.append("7. Signature valid: \(isValid ? "YES" : "NO")")

            // Verify with wrong data fails
            let wrongData = Data("Wrong message".utf8)
            let isInvalid = try enclaveService.verify(signature: signature, for: wrongData)
            results.append("8. Wrong data rejected: \(isInvalid ? "NO (BUG!)" : "YES")")

            results.append("\n=== ALL TESTS PASSED ===")
        } catch {
            results.append("\n=== ERROR ===")
            results.append(error.localizedDescription)
        }

        enclaveTestResult = results.joined(separator: "\n")
        isTestingEnclave = false
    }
}

#Preview {
    ContentView()
}
