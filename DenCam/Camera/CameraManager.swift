import AVFoundation
import UIKit

// CameraManager owns the AVCaptureSession and exposes a preview layer.
// ViewController composes this class — it does not subclass it.
//
// All session configuration runs on a dedicated serial queue (`sessionQueue`)
// to avoid blocking the main thread. The preview layer is safe to add to a
// UIView on the main thread because CALayer operations are thread-safe for display.

class CameraManager: NSObject {

    // MARK: - Public Properties

    // The preview layer that ViewController adds to its view hierarchy.
    // It's created once and connected to the capture session.
    let previewLayer = AVCaptureVideoPreviewLayer()

    // Callback for each video frame — ViewController sets this to feed
    // pixel buffers to MotionDetector.
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Private Properties

    // The capture session that connects camera input to outputs.
    private let captureSession = AVCaptureSession()

    // Serial queue dedicated to session configuration and start/stop.
    // AVCaptureSession is not thread-safe, so all mutations go through this queue.
    private let sessionQueue = DispatchQueue(label: "com.dencam.sessionQueue")

    // Dedicated queue for video frame delivery to avoid blocking the session queue.
    private let videoOutputQueue = DispatchQueue(label: "com.dencam.videoOutputQueue")

    // MARK: - Public Methods

    /// Requests camera permission and configures the capture session.
    /// The completion handler is called on the main thread with:
    ///   - `true` if the session is configured and running
    ///   - `false` if permission was denied or configuration failed
    func configure(completion: @escaping (Bool) -> Void) {
        // Check current authorization status for video capture
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Already have permission — go straight to setup
            sessionQueue.async { [weak self] in
                let success = self?.setupSession() ?? false
                DispatchQueue.main.async { completion(success) }
            }

        case .notDetermined:
            // First launch — ask the user for permission.
            // requestAccess calls its handler on an arbitrary queue,
            // so we hop to sessionQueue for setup.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                self?.sessionQueue.async {
                    let success = self?.setupSession() ?? false
                    DispatchQueue.main.async { completion(success) }
                }
            }

        case .denied, .restricted:
            // User previously denied or device policy restricts camera
            DispatchQueue.main.async { completion(false) }

        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    /// Starts the capture session on the session queue.
    /// Safe to call even if already running — AVCaptureSession ignores redundant starts.
    func start() {
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    /// Stops the capture session on the session queue.
    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Private Methods

    /// Configures the capture session with a back camera input and video data output.
    /// Must be called on `sessionQueue`. Returns true on success.
    private func setupSession() -> Bool {
        captureSession.beginConfiguration()

        // Use high preset — good balance of quality and performance for recording
        captureSession.sessionPreset = .high

        // Find the back wide-angle camera (the default rear camera)
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            print("[CameraManager] No back camera found")
            captureSession.commitConfiguration()
            return false
        }

        // Create an input from the camera device and add it to the session
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                print("[CameraManager] Could not add camera input to session")
                captureSession.commitConfiguration()
                return false
            }
        } catch {
            print("[CameraManager] Error creating camera input: \(error)")
            captureSession.commitConfiguration()
            return false
        }

        // Add video data output for frame-by-frame access (motion detection)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("[CameraManager] Could not add video data output to session")
        }

        captureSession.commitConfiguration()

        // Wire the preview layer to the session so it displays camera frames.
        // previewLayer.session can be set from any thread.
        previewLayer.session = captureSession
        previewLayer.videoGravity = .resizeAspectFill

        // Start running — frames begin flowing to the preview layer
        captureSession.startRunning()

        return true
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
