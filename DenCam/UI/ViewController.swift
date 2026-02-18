import UIKit

// ViewController is the main (and currently only) screen.
// It hosts the camera preview full-screen and handles the permission flow.
// It composes CameraManager rather than inheriting from it —
// CameraManager handles AVFoundation, ViewController handles UIKit.

class ViewController: UIViewController {

    // MARK: - Properties

    // CameraManager owns the capture session and preview layer.
    // ViewController just adds the preview layer to its view hierarchy.
    private let cameraManager = CameraManager()

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
