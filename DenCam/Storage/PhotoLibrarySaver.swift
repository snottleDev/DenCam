import Photos

// PhotoLibrarySaver handles saving recorded video files to the user's Photos library.
// It requests write-only permission (.addOnly) the first time it's called — this is
// the minimum permission needed to save videos without reading the user's photo library.
//
// After a successful save, the temp file is deleted to reclaim disk space.

class PhotoLibrarySaver {

    // MARK: - Public Properties

    // Called after a successful save with the new asset's local identifier.
    var onSaveComplete: ((String) -> Void)?

    // Called when saving fails (permission denied, disk error, etc.).
    var onSaveError: ((Error) -> Void)?

    // MARK: - Public Methods

    /// Saves the video at the given URL to the Photos library.
    /// Requests permission if needed. Deletes the temp file on success.
    func saveVideo(at url: URL) {
        // Check current photo library authorization
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            // Already have permission — save immediately
            performSave(at: url)

        case .notDetermined:
            // First time — request permission, then save if granted
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    self?.performSave(at: url)
                } else {
                    let error = PhotoLibrarySaverError.permissionDenied
                    print("[PhotoLibrarySaver] Permission denied")
                    self?.onSaveError?(error)
                }
            }

        case .denied, .restricted:
            let error = PhotoLibrarySaverError.permissionDenied
            print("[PhotoLibrarySaver] Permission denied (previously)")
            onSaveError?(error)

        @unknown default:
            let error = PhotoLibrarySaverError.permissionDenied
            onSaveError?(error)
        }
    }

    // MARK: - Private Methods

    private func performSave(at url: URL) {
        var assetID: String?

        PHPhotoLibrary.shared().performChanges({
            // Create a new video asset from the temp file
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }) { [weak self] success, error in
            if success, let id = assetID {
                print("[PhotoLibrarySaver] Saved video, asset ID: \(id)")
                self?.onSaveComplete?(id)

                // Delete the temp file now that it's safely in the Photos library
                try? FileManager.default.removeItem(at: url)
            } else {
                let saveError = error ?? PhotoLibrarySaverError.unknown
                print("[PhotoLibrarySaver] Failed to save: \(saveError.localizedDescription)")
                self?.onSaveError?(saveError)
                // Don't delete the temp file on failure — allows retry later
            }
        }
    }
}

// MARK: - Error Types

enum PhotoLibrarySaverError: LocalizedError {
    case permissionDenied
    case unknown

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library permission denied. Go to Settings → DenCam to enable."
        case .unknown:
            return "Unknown error saving to Photos library."
        }
    }
}
