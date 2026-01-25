//
//  ContentView.swift
//  ExampleApp
//

import SignedShotSDK
import SwiftUI

struct ContentView: View {
    @StateObject private var captureService = CaptureService()
    @State private var lastCapturedPhoto: CapturedPhoto?
    @State private var errorMessage: String?
    @State private var savedPhotoURL: URL?
    @State private var isSetup = false

    private let storage = PhotoStorage()

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
            await setupCamera()
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
                    Text("✓ \(url.lastPathComponent)")
                        .fontWeight(.medium)
                }
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(photo.jpegData.count), countStyle: .file))")
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
                    .fill(.white)
                    .frame(width: 70, height: 70)

                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)

                if captureService.isCaptureInProgress {
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .disabled(captureService.isCaptureInProgress || !isSetup)
    }

    // MARK: - Actions

    private func setupCamera() async {
        do {
            try await captureService.setupSession()
            captureService.startSession()
            isSetup = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capturePhoto() async {
        do {
            let photo = try await captureService.capturePhoto()
            lastCapturedPhoto = photo

            // Save to Documents folder
            let url = try storage.save(photo)
            savedPhotoURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
