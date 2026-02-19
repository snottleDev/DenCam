import AVFoundation

// RecordingManager wraps AVAssetWriter to record video frames to a .mov file.
// ViewController calls startRecording() / stopRecording() based on the motion
// detection state machine. While recording, CameraManager feeds sample buffers
// via appendSampleBuffer().
//
// All AVAssetWriter operations run on `recordingQueue` to avoid threading issues.

class RecordingManager {

    // MARK: - Public Properties

    // Called on recordingQueue when a recording finishes successfully.
    // The URL points to the temp .mov file ready to be saved to Photos.
    var onRecordingComplete: ((URL) -> Void)?

    // Called on recordingQueue when recording fails.
    var onRecordingError: ((Error) -> Void)?

    // MARK: - Private Properties

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var currentFileURL: URL?

    // True after startRecording() succeeds, false after stopRecording() completes.
    private var isRecording = false

    // The first frame's timestamp is used to start the AVAssetWriter session.
    // We can't call startSession() in startRecording() because we don't have
    // a timestamp yet — it comes from the first sample buffer.
    private var isFirstFrame = true

    // Serial queue for all AVAssetWriter operations.
    // Never access assetWriter / assetWriterInput from another queue.
    private let recordingQueue = DispatchQueue(label: "com.dencam.recordingQueue")

    // MARK: - Public Methods

    /// Prepares a new AVAssetWriter and transitions to recording state.
    /// Call this from the main thread — work is dispatched to recordingQueue.
    func startRecording() {
        recordingQueue.async { [weak self] in
            self?.beginRecording()
        }
    }

    /// Appends a video sample buffer to the current recording.
    /// Called from CameraManager's videoOutputQueue — dispatches to recordingQueue.
    /// Silently drops frames if not recording or if the writer isn't ready.
    func appendSampleBuffer(_ buffer: CMSampleBuffer) {
        recordingQueue.async { [weak self] in
            self?.append(buffer)
        }
    }

    /// Finishes writing and closes the file. The completion handler receives
    /// the temp file URL on success, or nil on failure.
    /// Call this from the main thread — work is dispatched to recordingQueue.
    func stopRecording(completion: @escaping (URL?) -> Void) {
        recordingQueue.async { [weak self] in
            self?.finishRecording(completion: completion)
        }
    }

    // MARK: - Private Methods

    private func beginRecording() {
        // Generate a unique filename in the temp directory
        let fileName = "DenCam_\(Self.timestampString()).mov"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // Remove any leftover file at this path (shouldn't happen with timestamps, but safe)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

            // Video settings — H.264, dimensions will be set from the first frame.
            // We use 0x0 here as placeholders; the actual dimensions come from
            // the format description of the first sample buffer.
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            // Real-time source (camera) — AVAssetWriter should expect irregular timing
            input.expectsMediaDataInRealTime = true

            if writer.canAdd(input) {
                writer.add(input)
            } else {
                print("[RecordingManager] Could not add video input to asset writer")
                return
            }

            // Start writing — the session start time is deferred to the first frame
            writer.startWriting()

            self.assetWriter = writer
            self.assetWriterInput = input
            self.currentFileURL = fileURL
            self.isFirstFrame = true
            self.isRecording = true

            print("[RecordingManager] Started writing to: \(fileURL.lastPathComponent)")

        } catch {
            print("[RecordingManager] Failed to create AVAssetWriter: \(error)")
            onRecordingError?(error)
        }
    }

    private func append(_ buffer: CMSampleBuffer) {
        guard isRecording,
              let writer = assetWriter,
              let input = assetWriterInput,
              writer.status == .writing else {
            return
        }

        // On the very first frame, start the writer session at this frame's timestamp.
        // This tells AVAssetWriter the time origin for the recording.
        if isFirstFrame {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
            writer.startSession(atSourceTime: timestamp)
            isFirstFrame = false
        }

        // Only append if the input is ready — otherwise drop the frame.
        // This is normal under heavy load; the camera produces frames faster
        // than the encoder can consume them.
        if input.isReadyForMoreMediaData {
            input.append(buffer)
        }
    }

    private func finishRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording,
              let writer = assetWriter,
              let input = assetWriterInput else {
            completion(nil)
            return
        }

        isRecording = false

        // Signal that no more frames are coming
        input.markAsFinished()

        let fileURL = currentFileURL

        // finishWriting is asynchronous — the completion handler fires when
        // the file is fully written to disk and ready to be moved/saved.
        writer.finishWriting { [weak self] in
            if writer.status == .completed {
                print("[RecordingManager] Finished writing: \(fileURL?.lastPathComponent ?? "?")")
                if let url = fileURL {
                    self?.onRecordingComplete?(url)
                }
                completion(fileURL)
            } else {
                let error = writer.error
                print("[RecordingManager] finishWriting failed: \(error?.localizedDescription ?? "unknown")")
                if let error = error {
                    self?.onRecordingError?(error)
                }
                completion(nil)
            }

            // Clean up references
            self?.assetWriter = nil
            self?.assetWriterInput = nil
            self?.currentFileURL = nil
        }
    }

    // MARK: - Helpers

    /// Returns a timestamp string for unique filenames: "2026-02-19_031245"
    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
