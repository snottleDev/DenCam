import UIKit

// ViewController is the main (and currently only) screen.
// It hosts the camera preview full-screen, the ROI overlay for motion detection,
// and handles the permission flow.
// It composes CameraManager rather than inheriting from it —
// CameraManager handles AVFoundation, ViewController handles UIKit.

class ViewController: UIViewController {

    // MARK: - Properties

    // CameraManager owns the capture session and preview layer.
    // ViewController just adds the preview layer to its view hierarchy.
    private let cameraManager = CameraManager()

    // Motion detection pipeline
    private let motionDetector = MotionDetector()
    private let settingsStore = SettingsStore()

    // ROI overlay drawn on top of the camera preview
    private let roiOverlay = ROIOverlayView()

    // Label shown when camera permission is denied, so the user knows what to do.
    private let permissionLabel: UILabel = {
        let label = UILabel()
        label.text = "Camera access is required.\nGo to Settings → DenCam → Camera."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true  // only shown when permission is denied
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Black background so the camera preview blends seamlessly
        view.backgroundColor = .black

        // Add the camera preview layer as a sublayer of the root view.
        // We insert it at index 0 so any future UI elements sit on top.
        view.layer.insertSublayer(cameraManager.previewLayer, at: 0)

        // Add ROI overlay on top of preview
        roiOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(roiOverlay)
        NSLayoutConstraint.activate([
            roiOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            roiOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            roiOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            roiOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Load persisted settings
        let savedROI = settingsStore.roiRect
        roiOverlay.roiRect = savedROI
        motionDetector.roiRect = savedROI
        motionDetector.sensitivity = settingsStore.sensitivity

        // Wire frame delivery: CameraManager → MotionDetector
        cameraManager.onFrame = { [weak self] buffer in
            self?.motionDetector.processFrame(buffer)
        }

        // Wire motion detection feedback: MotionDetector → ROI overlay
        motionDetector.onMotionDetected = { [weak self] detected in
            DispatchQueue.main.async {
                self?.roiOverlay.isMotionDetected = detected
            }
        }

        // Wire ROI changes: overlay → MotionDetector + SettingsStore
        roiOverlay.onROIChanged = { [weak self] newRect in
            self?.motionDetector.roiRect = newRect
            self?.settingsStore.roiRect = newRect
        }

        // Add the permission label centered in the view
        permissionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(permissionLabel)
        NSLayoutConstraint.activate([
            permissionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            permissionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            permissionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            permissionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        // Ask CameraManager to request permission and set up the capture session.
        // The completion runs on the main thread.
        cameraManager.configure { [weak self] success in
            if !success {
                // Permission denied or session setup failed — show the guidance label
                self?.permissionLabel.isHidden = false
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Keep the preview layer sized to fill the entire view.
        // This is called whenever the view's bounds change (rotation, etc.).
        cameraManager.previewLayer.frame = view.bounds
    }

    // MARK: - Status Bar

    // Hide the status bar for a fully immersive camera preview
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
