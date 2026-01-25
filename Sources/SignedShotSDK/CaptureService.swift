import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

/// Result of a photo capture containing the raw JPEG data
public struct CapturedPhoto: Sendable {
    /// Raw JPEG bytes - never recompressed
    public let jpegData: Data

    /// Timestamp when the photo was captured
    public let capturedAt: Date

    /// Unique identifier for this capture
    public let captureId: UUID

    public init(jpegData: Data, capturedAt: Date, captureId: UUID) {
        self.jpegData = jpegData
        self.capturedAt = capturedAt
        self.captureId = captureId
    }
}

/// Errors that can occur during capture
public enum CaptureError: Error, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case captureInProgress
    case captureFailed(String)
    case noCameraDevice

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available"
        case .permissionDenied:
            return "Camera permission was denied"
        case .captureInProgress:
            return "A capture is already in progress"
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        case .noCameraDevice:
            return "No camera device found"
        }
    }
}

/// Service for capturing photos with preserved JPEG bytes
@MainActor
public final class CaptureService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var isCaptureInProgress = false

    // MARK: - Private Properties

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureDevice: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var photoContinuation: CheckedContinuation<CapturedPhoto, Error>?

    // MARK: - Public Methods

    /// Request camera permission
    public func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Set up the capture session
    public func setupSession() async throws {
        guard await requestPermission() else {
            throw CaptureError.permissionDenied
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.noCameraDevice
        }

        captureDevice = device

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // Add input
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw CaptureError.cameraUnavailable
        }
        captureSession.addInput(input)

        // Add output
        guard captureSession.canAddOutput(photoOutput) else {
            captureSession.commitConfiguration()
            throw CaptureError.cameraUnavailable
        }
        captureSession.addOutput(photoOutput)

        // Configure for highest quality JPEG
        photoOutput.maxPhotoQualityPrioritization = .quality

        captureSession.commitConfiguration()
    }

    /// Start the capture session
    public func startSession() {
        guard !captureSession.isRunning else { return }

        Task.detached { [captureSession] in
            captureSession.startRunning()
        }

        isSessionRunning = true
    }

    /// Stop the capture session
    public func stopSession() {
        guard captureSession.isRunning else { return }

        Task.detached { [captureSession] in
            captureSession.stopRunning()
        }

        isSessionRunning = false
    }

    /// Capture a photo and return the raw JPEG data
    public func capturePhoto() async throws -> CapturedPhoto {
        guard !isCaptureInProgress else {
            throw CaptureError.captureInProgress
        }

        isCaptureInProgress = true

        defer {
            isCaptureInProgress = false
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Get the preview layer for displaying the camera feed
    public func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = previewLayer {
            return existing
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                photoContinuation?.resume(throwing: CaptureError.captureFailed(error.localizedDescription))
                photoContinuation = nil
                return
            }

            // Get the exact JPEG bytes - this is critical for integrity
            guard let jpegData = photo.fileDataRepresentation() else {
                photoContinuation?.resume(throwing: CaptureError.captureFailed("Failed to get JPEG data"))
                photoContinuation = nil
                return
            }

            let capturedPhoto = CapturedPhoto(
                jpegData: jpegData,
                capturedAt: Date(),
                captureId: UUID()
            )

            photoContinuation?.resume(returning: capturedPhoto)
            photoContinuation = nil
        }
    }
}
