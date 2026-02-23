import UIKit

// SensitivityPreviewViewController is a compact half-height sheet that lets the
// user tune the sensitivity slider while watching the live camera feed behind it.
//
// It's presented with UISheetPresentationController at .medium detent so the
// camera preview, ROI overlay, and bounding box overlay are all visible above.
//
// ViewController drives this view controller:
//   - onSensitivityChanged fires on every slider tick → pushed into MotionDetector
//   - onDone fires when the user taps Done → ViewController saves and cleans up
//   - setMotionActive(_:) is called by ViewController from the motion callback
//     so the indicator in this sheet reflects live detection state

class SensitivityPreviewViewController: UIViewController {

    // MARK: - Callbacks

    // Called on every slider change — ViewController applies this to MotionDetector.
    var onSensitivityChanged: ((Float) -> Void)?

    // Called when the user taps Done with the final slider value.
    var onDone: ((Float) -> Void)?

    // MARK: - Public Methods

    /// Updates the motion indicator to reflect the current detection state.
    /// Called from ViewController's motionDetector.onMotionDetected callback.
    /// Safe to call from the main thread.
    func setMotionActive(_ active: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.motionPill.backgroundColor = active
                ? UIColor.systemGreen
                : UIColor.systemGray.withAlphaComponent(0.25)
        }
        motionPill.setTitle(active ? "  Motion detected  " : "  No motion  ", for: .normal)
        motionPill.setTitleColor(active ? .white : .secondaryLabel, for: .normal)
    }

    // MARK: - Private Properties

    private var currentSensitivity: Float

    private let slider: UISlider = {
        let s = UISlider()
        s.minimumValue = 0
        s.maximumValue = 1
        return s
    }()

    // Fixed-width label shows the current percentage so the slider doesn't jump around
    private let percentLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .right
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        return label
    }()

    // Pill-shaped button used as a visual indicator — not interactive (userInteractionEnabled = false)
    private let motionPill: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("  No motion  ", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.backgroundColor = UIColor.systemGray.withAlphaComponent(0.25)
        button.layer.cornerRadius = 14
        button.isUserInteractionEnabled = false  // display only
        return button
    }()

    // MARK: - Init

    init(sensitivity: Float) {
        self.currentSensitivity = sensitivity
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        title = "Sensitivity"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        slider.value = currentSensitivity
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        updatePercentLabel()

        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        // Row 1: slider + percentage
        let sliderRow = UIStackView(arrangedSubviews: [slider, percentLabel])
        sliderRow.axis = .horizontal
        sliderRow.spacing = 12
        sliderRow.alignment = .center

        // Row 2: scale labels under the slider
        let moreLabel = makeScaleLabel("More sensitive")
        let lessLabel = makeScaleLabel("Less sensitive")
        let scaleRow = UIStackView(arrangedSubviews: [moreLabel, UIView(), lessLabel])
        scaleRow.axis = .horizontal

        // Row 3: motion indicator pill
        // Wrap in a left-aligned container so the pill doesn't stretch full width
        let pillContainer = UIView()
        motionPill.translatesAutoresizingMaskIntoConstraints = false
        pillContainer.addSubview(motionPill)
        NSLayoutConstraint.activate([
            motionPill.topAnchor.constraint(equalTo: pillContainer.topAnchor),
            motionPill.bottomAnchor.constraint(equalTo: pillContainer.bottomAnchor),
            motionPill.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor),
            motionPill.heightAnchor.constraint(equalToConstant: 28)
        ])

        // Row 4: instruction text
        let hintLabel = UILabel()
        hintLabel.text = "Watch the green ROI border above — it lights up when motion is detected at the current threshold."
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [sliderRow, scaleRow, pillContainer, hintLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func makeScaleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        return label
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        currentSensitivity = slider.value
        updatePercentLabel()
        onSensitivityChanged?(slider.value)
    }

    @objc private func doneTapped() {
        onDone?(currentSensitivity)
    }

    // MARK: - Helpers

    private func updatePercentLabel() {
        percentLabel.text = "\(Int(slider.value * 100))%"
    }
}
