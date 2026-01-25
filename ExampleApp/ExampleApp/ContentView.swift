//
//  ContentView.swift
//  ExampleApp
//

import SignedShotSDK
import SwiftUI
import UIKit

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

    private let storage = PhotoStorage()
    private let client: SignedShotClient

    init() {
        // Configure the SignedShot client
        let config = SignedShotConfiguration(
            baseURLString: "https://dev-api.signedshot.io",
            publisherId: "9a5b1062-a8fe-4871-bdc1-fe54e96cbf1c"
        )!
        client = SignedShotClient(configuration: config)
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
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack {
            Text("SignedShot")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // Registration status indicator
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
            Text("Ready to Capture")
                .font(.headline)
                .foregroundColor(.white)

            Text("Start a capture session to take an authenticated photo")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

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
                    Text(isStartingSession ? "Starting..." : "Start Session")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.green)
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

            let remaining = session.expiresAt.timeIntervalSinceNow
            if remaining > 0 {
                Text("Expires in \(Int(remaining))s")
                    .font(.caption2)
                    .foregroundColor(remaining < 30 ? .orange : .gray)
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

            Button("Dismiss") {
                lastCapturedPhoto = nil
                savedPhotoURL = nil
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.top, 4)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(12)
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                lastCapturedPhoto = nil
                savedPhotoURL = nil
            }
        }
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
        isSetup && hasActiveSession && !captureService.isCaptureInProgress
    }

    // MARK: - Actions

    private func initialize() async {
        // Check registration status
        isDeviceRegistered = await client.isDeviceRegistered
        deviceId = await client.deviceId

        // Setup camera
        await setupCamera()
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
            // Registration handles external_id internally
            // If 409 conflict occurs, it auto-retries with a new ID
            let response = try await client.registerDevice()

            isDeviceRegistered = true
            deviceId = response.deviceId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSession() async {
        isStartingSession = true
        defer { isStartingSession = false }

        do {
            let session = try await client.createCaptureSession()
            currentSession = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capturePhoto() async {
        guard hasActiveSession else {
            errorMessage = "No active session"
            return
        }

        do {
            let photo = try await captureService.capturePhoto()
            lastCapturedPhoto = photo

            // Save to Documents folder
            let url = try storage.save(photo)
            savedPhotoURL = url

            // Clear session after capture (one-time use)
            currentSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
