import AVFoundation
import CoreImage
import UIKit

// RecordingManager wraps AVAssetWriter to record video frames to a .mov file.
// ViewController calls startRecording() / stopRecording() based on the motion
// detection state machine. While recording, CameraManager feeds sample buffers
// via appendSampleBuffer().
//
// When showBoundingBoxes is true, frames are composited through CIContext so
// we can draw a yellow rectangle around the detected motion region before
// encoding. When false, raw CMSampleBuffers are appended directly (zero overhead).
//
// All AVAssetWriter operations run on `recordingQueue` to avoid threading issues.

class RecordingManager {

    // MARK: - Public Properties

    // Called on recordingQueue when a recording finishes successfully.
    // The URL points to the temp .mov file ready to be saved to Photos.
    var onRecordingComplete: ((URL) -> Void)?

    // Called on recordingQueue when recording fails.
    var onRecordingError: ((Error) -> Void)?

    // When true, bounding boxes are burned into the recorded video.
    // Set this before starting a recording — changing mid-recording has no effect
    // on the writer setup but the drawing will toggle immediately.
    var showBoundingBoxes: Bool = false

    // The current motion bounding box in normalized coordinates (0–1).
    // Updated by ViewController from the MotionDetector callback.
    // Read on recordingQueue — written from videoOutputQueue via ViewController,
    // so we use an atomic-friendly pattern (simple value type, no lock needed
    // for single-writer/single-reader on 64-bit).
    var currentMotionRect: CGRect?

    // MARK: - Private Properties

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var currentFileURL: URL?

    // Pixel buffer adaptor — used when showBoundingBoxes is true.
    // Provides a CVPixelBufferPool for allocating output buffers efficiently.
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // CIContext for converting YCbCr camera frames to BGRA for CoreGraphics drawing.
    // Created once and reused — CIContext creation is expensive.
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // True after startRecording() succeeds, false after stopRecording() completes.
    private var isRecording = false

    // The first frame's timestamp is used to start the AVAssetWriter session.
    // We can't call startSession() in startRecording() because we don't have
    // a timestamp yet — it comes from the first sample buffer.
    private var isFirstFrame = true

    // Whether this recording session uses the bounding box path.
    // Captured at recording start so we don't change modes mid-recording.
    private var recordingWithBoxes = false

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
        // Capture the bounding box setting at recording start
        recordingWithBoxes = showBoundingBoxes

        // Generate a unique filename in the temp directory
        let fileName = "DenCam_\(Self.timestampString()).mov"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // Remove any leftover file at this path (shouldn't happen with timestamps, but safe)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

            // Video settings — H.264 at 1920x1080
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

            // When burning bounding boxes, we need a pixel buffer adaptor to
            // append CVPixelBuffers (after drawing) instead of raw CMSampleBuffers.
            if recordingWithBoxes {
                let adaptorAttrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 1920,
                    kCVPixelBufferHeightKey as String: 1080
                ]
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: adaptorAttrs
                )
                self.pixelBufferAdaptor = adaptor
            }

            // Start writing — the session start time is deferred to the first frame
            writer.startWriting()

            self.assetWriter = writer
            self.assetWriterInput = input
            self.currentFileURL = fileURL
            self.isFirstFrame = true
            self.isRecording = true

            print("[RecordingManager] Started writing to: \(fileURL.lastPathComponent) (boxes: \(recordingWithBoxes))")

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

        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)

        // On the very first frame, start the writer session at this frame's timestamp.
        // This tells AVAssetWriter the time origin for the recording.
        if isFirstFrame {
            writer.startSession(atSourceTime: timestamp)
            isFirstFrame = false
        }

        // Only append if the input is ready — otherwise drop the frame.
        // This is normal under heavy load; the camera produces frames faster
        // than the encoder can consume them.
        guard input.isReadyForMoreMediaData else { return }

        if recordingWithBoxes {
            // Bounding box path: render frame + box to a new pixel buffer
            appendWithBoundingBox(buffer, at: timestamp)
        } else {
            // Fast path: append raw sample buffer directly
            input.append(buffer)
        }
    }

    /// Composites the bounding box onto the frame and appends via the pixel buffer adaptor.
    private func appendWithBoundingBox(_ buffer: CMSampleBuffer, at timestamp: CMTime) {
        guard let adaptor = pixelBufferAdaptor,
              let sourcePixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            return
        }

        // Get an output pixel buffer from the adaptor's pool (efficient reuse)
        guard let pool = adaptor.pixelBufferPool else {
            print("[RecordingManager] Pixel buffer pool not available yet")
            return
        }

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return
        }

        // Convert the camera's YCbCr frame to BGRA via CIImage + CIContext
        let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        ciContext.render(ciImage, to: output)

        // Draw the bounding box if one exists
        if let motionRect = currentMotionRect {
            drawBoundingBox(motionRect, on: output)
        }

        // Append the composited frame
        adaptor.append(output, withPresentationTime: timestamp)
    }

    /// Draws a yellow rectangle on a BGRA pixel buffer using CoreGraphics.
    private func drawBoundingBox(_ normalizedRect: CGRect, on pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        // Create a CGContext that draws directly into the pixel buffer's memory
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        // CoreGraphics has origin at bottom-left, but our normalized coords
        // have origin at top-left. Flip the Y axis.
        let boxRect = CGRect(
            x: normalizedRect.origin.x * CGFloat(width),
            y: (1.0 - normalizedRect.origin.y - normalizedRect.size.height) * CGFloat(height),
            width: normalizedRect.size.width * CGFloat(width),
            height: normalizedRect.size.height * CGFloat(height)
        )

        context.setStrokeColor(UIColor.systemYellow.cgColor)
        context.setLineWidth(3)
        context.stroke(boxRect)
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
            self?.pixelBufferAdaptor = nil
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
