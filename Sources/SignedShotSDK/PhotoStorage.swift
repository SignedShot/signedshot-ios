import Foundation

/// Manages storage of captured photos in the app's Documents directory
public final class PhotoStorage: Sendable {
    /// The folder name within Documents where photos are stored
    public let folderName: String

    /// Initialize with a custom folder name
    public init(folderName: String = "SignedShot") {
        self.folderName = folderName
    }

    /// Get the URL for the SignedShot folder, creating it if needed
    public func getFolderURL() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderURL = documentsURL.appendingPathComponent(folderName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        return folderURL
    }

    /// Save a captured photo to storage
    /// - Returns: The URL where the photo was saved
    @discardableResult
    public func save(_ photo: CapturedPhoto) throws -> URL {
        let folderURL = try getFolderURL()
        let filename = generateFilename(for: photo)
        let fileURL = folderURL.appendingPathComponent(filename)

        try photo.jpegData.write(to: fileURL)

        return fileURL
    }

    /// Save a sidecar file alongside a photo
    /// - Parameters:
    ///   - sidecarData: The sidecar JSON data
    ///   - photoURL: The URL of the photo file
    /// - Returns: The URL where the sidecar was saved
    @discardableResult
    public func saveSidecar(_ sidecarData: Data, for photoURL: URL) throws -> URL {
        let sidecarURL = sidecarURL(for: photoURL)
        try sidecarData.write(to: sidecarURL)
        return sidecarURL
    }

    /// Get the sidecar URL for a photo URL
    public func sidecarURL(for photoURL: URL) -> URL {
        photoURL.deletingPathExtension().appendingPathExtension("sidecar.json")
    }

    /// List all saved photos
    public func listPhotos() throws -> [URL] {
        let folderURL = try getFolderURL()

        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
    }

    /// Delete a photo at the given URL
    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)

        // Also delete sidecar if it exists
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("sidecar.json")
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            try FileManager.default.removeItem(at: sidecarURL)
        }
    }

    /// Generate a filename for a captured photo
    private func generateFilename(for photo: CapturedPhoto) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: photo.capturedAt)
        return "photo_\(timestamp).jpg"
    }
}
