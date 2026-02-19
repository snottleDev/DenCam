import UIKit

// ViewController is the main (and currently only) screen.
// It hosts the camera preview full-screen, the ROI overlay for motion detection,
// and manages the recording state machine.
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

    // Screen brightness management — dims after inactivity
    private lazy var brightnessManager = BrightnessManager(dimDelay: settingsStore.dimDelay)

    // Thermal state monitoring — warns at .serious, stops recording at .critical
    private let thermalMonitor = ThermalMonitor()

    // Storage quota enforcement — blocks new recordings when quota exceeded
    private lazy var storageManager = StorageManager(quotaGB: settingsStore.storageQuotaGB)

    // Recording pipeline
    private let recordingManager = RecordingManager()
    private let photoLibrarySaver = PhotoLibrarySaver()

    // Recording state machine — tracks whether we're idle, actively recording,
    // or in the post-motion tail period waiting for more motion.
    private enum RecordingState {
        case idle              // No motion, not recording
        case recording         // Motion detected, actively recording
        case recordingWithTail // Motion stopped, recording continues for tail duration
    }
    private var recordingState: RecordingState = .idle

    // Timer for the post-motion tail — fires after N seconds of no motion
    // to stop recording and save the file.
    private var tailTimer: Timer?

    // Gear button in the top-right corner to open settings
    private let settingsButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        button.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white
        return button
    }()

    // True when thermal shutdown has halted recording — prevents new recordings
    // until the device cools back to .serious or below.
    private var thermalShutdown = false

    // Label shown when the device is overheating
    private let thermalWarningLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .boldSystemFont(ofSize: 16)
        label.isHidden = true
        return label
    }()

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

        // Wire sample buffer delivery: CameraManager → RecordingManager
        // Only forward frames when we're actually recording to avoid unnecessary work.
        cameraManager.onSampleBuffer = { [weak self] buffer in
            guard let self = self, self.recordingState != .idle else { return }
            self.recordingManager.appendSampleBuffer(buffer)
        }

        // Wire motion detection: MotionDetector → ROI overlay + recording state machine
        motionDetector.onMotionDetected = { [weak self] detected in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.roiOverlay.isMotionDetected = detected
                self.handleMotionDetection(detected)
            }
        }

        // Wire ROI changes: overlay → MotionDetector + SettingsStore
        // Also reset the dim timer — dragging ROI corners counts as user activity.
        roiOverlay.onROIChanged = { [weak self] newRect in
            self?.motionDetector.roiRect = newRect
            self?.settingsStore.roiRect = newRect
            self?.brightnessManager.userDidTouch()
        }

        // Log recording errors
        recordingManager.onRecordingError = { error in
            print("[ViewController] Recording error: \(error.localizedDescription)")
        }

        // Log photo library save results
        photoLibrarySaver.onSaveComplete = { assetID in
            print("[ViewController] Video saved to Photos: \(assetID)")
        }
        photoLibrarySaver.onSaveError = { error in
            print("[ViewController] Failed to save video: \(error.localizedDescription)")
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

        // Add thermal warning label above the permission label
        thermalWarningLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thermalWarningLabel)
        NSLayoutConstraint.activate([
            thermalWarningLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            thermalWarningLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            thermalWarningLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            thermalWarningLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        // Wire thermal monitoring — warn at .serious, stop recording at .critical
        thermalMonitor.onStateChange = { [weak self] state in
            self?.handleThermalStateChange(state)
        }

        // Wire recording completion to storage tracking.
        // trackFile() is called before Photos save so we count the bytes even
        // if the save fails. This overwrites the existing onRecordingComplete.
        recordingManager.onRecordingComplete = { [weak self] tempURL in
            self?.storageManager.trackFile(at: tempURL)
            self?.photoLibrarySaver.saveVideo(at: tempURL)
        }

        // Add the settings gear button in the top-right corner
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        // Ask CameraManager to request permission and set up the capture session.
        // The completion runs on the main thread.
        cameraManager.configure { [weak self] success in
            guard let self = self else { return }
            if success {
                self.brightnessManager.start(in: self.view)
                self.thermalMonitor.start()
            } else {
                // Permission denied or session setup failed — show the guidance label
                self.permissionLabel.isHidden = false
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

    // MARK: - Settings

    @objc private func settingsTapped() {
        let settingsVC = SettingsViewController(settings: settingsStore)

        // When settings are dismissed, re-apply any values that may have changed
        settingsVC.onDismiss = { [weak self] in
            guard let self = self else { return }
            self.motionDetector.sensitivity = self.settingsStore.sensitivity
            self.storageManager.quotaGB = self.settingsStore.storageQuotaGB
        }

        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If the screen was dimmed, this tap is just a "wake up" —
        // don't pass it to the ROI overlay or other UI.
        if brightnessManager.userDidTouch() {
            return
        }
        super.touchesBegan(touches, with: event)
    }

    // MARK: - Thermal State Handling

    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        switch state {

        case .critical:
            // Device is dangerously hot — stop recording immediately and warn.
            // Briefly restore screen brightness so the user can see the warning
            // even if the screen was dimmed.
            thermalShutdown = true
            thermalWarningLabel.text = "Overheating — recording stopped.\nLet the device cool down."
            thermalWarningLabel.isHidden = false
            brightnessManager.userDidTouch()

            if recordingState != .idle {
                cancelTailTimer()
                recordingState = .idle
                recordingManager.stopRecording { url in
                    if let url = url {
                        print("[ViewController] Thermal shutdown — saved: \(url.lastPathComponent)")
                    }
                }
                print("[ViewController] Thermal critical — stopped recording")
            }

        case .serious:
            // Getting warm — show a warning but let recording continue.
            // Also clear thermal shutdown if we were previously critical.
            thermalShutdown = false
            thermalWarningLabel.text = "Device is warm — monitoring temperature."
            thermalWarningLabel.isHidden = false

        case .nominal, .fair:
            // All clear — hide any warning and allow recording again.
            thermalShutdown = false
            thermalWarningLabel.isHidden = true

        @unknown default:
            break
        }
    }

    // MARK: - Recording State Machine
    //
    // State transitions:
    //   (idle, motion=true)            → start recording
    //   (recording, motion=false)      → start tail timer
    //   (recordingWithTail, motion=true) → cancel timer, back to recording
    //   (tail timer fires)             → stop recording, save to Photos
    //   all other combinations         → no-op

    private func handleMotionDetection(_ detected: Bool) {
        switch (recordingState, detected) {

        case (.idle, true):
            // Motion detected while idle → start recording (if allowed)
            if thermalShutdown {
                print("[ViewController] Motion detected but thermal shutdown active — skipping")
                return
            }
            if !storageManager.canStartRecording() {
                print("[ViewController] Motion detected but storage quota exceeded — skipping")
                return
            }
            recordingState = .recording
            recordingManager.startRecording()
            print("[ViewController] Motion detected — started recording")

        case (.recording, false):
            // Motion stopped while recording → start the tail timer.
            // If the animal moves again before the timer fires, we cancel it.
            recordingState = .recordingWithTail
            startTailTimer()
            print("[ViewController] Motion stopped — tail timer started")

        case (.recordingWithTail, true):
            // Motion detected again during tail → cancel timer, keep recording.
            // This prevents short pauses from splitting a single activity into
            // multiple clips.
            recordingState = .recording
            cancelTailTimer()
            print("[ViewController] Motion during tail — cancelled timer, continuing")

        case (.recording, true),
             (.idle, false),
             (.recordingWithTail, false):
            // No state change needed:
            // - recording + motion: keep recording
            // - idle + no motion: stay idle
            // - tail + no motion: timer is still running
            break
        }
    }

    private func startTailTimer() {
        cancelTailTimer()

        let tailDuration = settingsStore.postMotionTail
        tailTimer = Timer.scheduledTimer(
            withTimeInterval: tailDuration,
            repeats: false
        ) { [weak self] _ in
            self?.handleTailExpired()
        }
    }

    private func cancelTailTimer() {
        tailTimer?.invalidate()
        tailTimer = nil
    }

    private func handleTailExpired() {
        print("[ViewController] Tail expired — stopping recording")
        recordingState = .idle
        tailTimer = nil

        recordingManager.stopRecording { url in
            if let url = url {
                print("[ViewController] Recording saved to: \(url.lastPathComponent)")
            } else {
                print("[ViewController] Recording stop returned no file")
            }
        }
    }
}
