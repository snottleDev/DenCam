import Foundation

// StorageManager tracks how much video data DenCam has saved to the
// Photos library during this session. Before each new recording starts,
// ViewController asks canStartRecording() to check whether the user's
// storage quota has been exceeded.
//
// Tracking is based on the size of temp files that RecordingManager
// creates. Each time a recording completes, ViewController calls
// trackFile(at:) with the temp URL before it gets saved to Photos.
//
// The quota is checked against cumulative bytes written this session,
// not the device's free disk space — the user controls how much DenCam
// is allowed to produce per overnight run.

class StorageManager {

    // MARK: - Properties

    // User-configured maximum gigabytes per session.
    // 0 means unlimited (no quota enforcement).
    var quotaGB: Double

    // Running total of bytes recorded this session.
    private(set) var bytesRecorded: Int64 = 0

    // MARK: - Init

    init(quotaGB: Double) {
        self.quotaGB = quotaGB
    }

    // MARK: - Public Methods

    /// Returns true if we're still under the storage quota, or if quota is 0 (unlimited).
    func canStartRecording() -> Bool {
        guard quotaGB > 0 else { return true }
        let quotaBytes = Int64(quotaGB * 1_073_741_824) // 1 GB = 1024^3 bytes
        let withinQuota = bytesRecorded < quotaBytes
        if !withinQuota {
            print("[StorageManager] Quota exceeded: \(formattedSize(bytesRecorded)) / \(formattedSize(quotaBytes))")
        }
        return withinQuota
    }

    /// Record the size of a completed video file against the session total.
    /// Call this when RecordingManager finishes writing a file (before Photos save).
    func trackFile(at url: URL) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            bytesRecorded += fileSize
            print("[StorageManager] Tracked \(formattedSize(fileSize)) — session total: \(formattedSize(bytesRecorded))")
        } catch {
            print("[StorageManager] Could not read file size: \(error.localizedDescription)")
        }
    }

    /// Resets the session byte counter. Called if the user explicitly resets,
    /// or at the start of a new overnight session.
    func resetSession() {
        bytesRecorded = 0
        print("[StorageManager] Session counter reset")
    }

    // MARK: - Helpers

    /// Formats a byte count as a human-readable string (e.g. "1.2 GB", "340 MB").
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
