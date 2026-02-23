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

    // Callback for full sample buffers — ViewController sets this to feed
    // CMSampleBuffer (with timing info) to RecordingManager for AVAssetWriter.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    // MARK: - Private Properties

    // The capture session that connects camera input to outputs.
    private let captureSession = AVCaptureSession()

    // Serial queue dedicated to session configuration and start/stop.
    // AVCaptureSession is not thread-safe, so all mutations go through this queue.
    private let sessionQueue = DispatchQueue(label: "com.dencam.sessionQueue")

    // Dedicated queue for video frame delivery to avoid blocking the session queue.
    private let videoOutputQueue = DispatchQueue(label: "com.dencam.videoOutputQueue")

    // The active camera device — stored after setup so we can lock/unlock it later.
    private var captureDevice: AVCaptureDevice?

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

    /// Locks exposure and white balance at their current automatically-determined values.
    ///
    /// Call this after auto-exposure has settled on the scene you want (e.g. the lit
    /// terrarium at night). Both will stay fixed until `unlockExposureAndWhiteBalance()`
    /// is called, preventing the camera from hunting or drifting during a long session.
    ///
    /// The completion handler is called on the main thread with `true` on success,
    /// `false` if the device isn't ready or locking isn't supported.
    func lockExposureAndWhiteBalance(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            do {
                // lockForConfiguration() is required before changing any device property.
                // It prevents other parts of the system from changing settings mid-write.
                try device.lockForConfiguration()

                // .locked means "hold the current automatically-set value, stop adjusting".
                // We check support first — some older devices may not support a given mode.
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }

                device.unlockForConfiguration()
                DispatchQueue.main.async { completion(true) }
            } catch {
                print("[CameraManager] Could not lock camera configuration: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    /// Restores continuous auto-exposure and auto-white-balance.
    ///
    /// The camera will begin adjusting again immediately. Call this if the lighting
    /// conditions change significantly and you want to re-lock at the new values.
    ///
    /// The completion handler is called on the main thread with `true` on success.
    func unlockExposureAndWhiteBalance(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            do {
                try device.lockForConfiguration()

                // .continuousAutoExposure / .continuousAutoWhiteBalance — the camera
                // monitors the scene and adjusts automatically, as it does by default.
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                device.unlockForConfiguration()
                DispatchQueue.main.async { completion(true) }
            } catch {
                print("[CameraManager] Could not unlock camera configuration: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
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

        // Store the device so lockExposureAndWhiteBalance() can reference it later.
        captureDevice = camera

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
        // Feed pixel buffer to motion detector
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            onFrame?(pixelBuffer)
        }

        // Feed full sample buffer (with timing) to recording manager
        onSampleBuffer?(sampleBuffer)
    }
}
