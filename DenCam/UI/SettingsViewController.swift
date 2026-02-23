import UIKit

// SettingsViewController presents user-configurable options in a standard
// iOS grouped table view. It reads current values from SettingsStore on
// appearance and writes changes back immediately.
//
// The caller provides a SettingsStore instance and an optional onDismiss
// callback so it can re-apply any changed values (e.g. sensitivity).

class SettingsViewController: UITableViewController {

    // MARK: - Properties

    // Shared settings store — the same instance used by ViewController
    private let settings: SettingsStore

    // Called when the settings screen is dismissed so the caller can
    // re-read any values that changed.
    var onDismiss: (() -> Void)?

    // Called when the user taps "Live Preview" in the sensitivity section.
    // SettingsViewController dismisses itself first, then fires this so
    // ViewController can present the sensitivity preview over the camera feed.
    var onOpenSensitivityPreview: (() -> Void)?

    // MARK: - Section / Row Layout
    //
    // Each section groups related settings. Rows are identified by their
    // index within the section.

    private enum Section: Int, CaseIterable {
        case detection  // Sensitivity
        case recording  // Post-motion tail
        case storage    // Storage quota
        case overlay    // Bounding boxes
        case display    // Dim delay
    }

    // MARK: - Controls
    //
    // We keep references to the controls so we can read their values
    // and update the detail labels when values change.

    private let sensitivitySlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        return slider
    }()

    // Label that shows the current sensitivity percentage next to the slider
    private let sensitivityValueLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        label.textAlignment = .right
        // Fixed width so the slider doesn't jump when the text changes width
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return label
    }()

    private let tailStepper: UIStepper = {
        let stepper = UIStepper()
        stepper.minimumValue = 5
        stepper.maximumValue = 60
        stepper.stepValue = 5
        return stepper
    }()

    private let tailValueLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        return label
    }()

    private let dimStepper: UIStepper = {
        let stepper = UIStepper()
        stepper.minimumValue = 10
        stepper.maximumValue = 120
        stepper.stepValue = 10
        return stepper
    }()

    private let dimValueLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        return label
    }()

    private let quotaStepper: UIStepper = {
        let stepper = UIStepper()
        stepper.minimumValue = 0   // 0 = unlimited
        stepper.maximumValue = 20
        stepper.stepValue = 1
        return stepper
    }()

    private let quotaValueLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        return label
    }()

    private let boundingBoxSwitch = UISwitch()

    // MARK: - Init

    init(settings: SettingsStore) {
        self.settings = settings
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Settings"

        // "Done" button in the top-right to dismiss the modal
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        // Load current values into the controls
        sensitivitySlider.value = settings.sensitivity
        tailStepper.value = settings.postMotionTail
        dimStepper.value = settings.dimDelay
        quotaStepper.value = settings.storageQuotaGB
        boundingBoxSwitch.isOn = settings.showBoundingBoxes

        // Update the value labels to match
        updateSensitivityLabel()
        updateTailLabel()
        updateDimLabel()
        updateQuotaLabel()

        // Wire up control actions
        sensitivitySlider.addTarget(self, action: #selector(sensitivityChanged), for: .valueChanged)
        tailStepper.addTarget(self, action: #selector(tailChanged), for: .valueChanged)
        dimStepper.addTarget(self, action: #selector(dimChanged), for: .valueChanged)
        quotaStepper.addTarget(self, action: #selector(quotaChanged), for: .valueChanged)
        boundingBoxSwitch.addTarget(self, action: #selector(boundingBoxChanged), for: .valueChanged)

        // Register a plain cell style for reuse
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // Only the Live Preview row (detection section, row 1) is tappable.
        guard Section(rawValue: indexPath.section) == .detection, indexPath.row == 1 else { return }

        // Dismiss the settings sheet, then tell ViewController to open the preview.
        // We dismiss first so the camera feed is unobscured when the preview appears.
        dismiss(animated: true) { [weak self] in
            self?.onOpenSensitivityPreview?()
        }
    }

    @objc private func sensitivityChanged() {
        settings.sensitivity = sensitivitySlider.value
        updateSensitivityLabel()
    }

    @objc private func tailChanged() {
        settings.postMotionTail = tailStepper.value
        updateTailLabel()
    }

    @objc private func dimChanged() {
        settings.dimDelay = dimStepper.value
        updateDimLabel()
    }

    @objc private func quotaChanged() {
        settings.storageQuotaGB = quotaStepper.value
        updateQuotaLabel()
    }

    @objc private func boundingBoxChanged() {
        settings.showBoundingBoxes = boundingBoxSwitch.isOn
    }

    // MARK: - Label Updates

    private func updateSensitivityLabel() {
        let percent = Int(sensitivitySlider.value * 100)
        sensitivityValueLabel.text = "\(percent)%"
    }

    private func updateTailLabel() {
        tailValueLabel.text = "\(Int(tailStepper.value))s"
    }

    private func updateDimLabel() {
        dimValueLabel.text = "\(Int(dimStepper.value))s"
    }

    private func updateQuotaLabel() {
        let value = Int(quotaStepper.value)
        quotaValueLabel.text = value == 0 ? "Off" : "\(value) GB"
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Detection has two rows: the slider and a "Live Preview" entry point.
        // All other sections have exactly one row.
        return Section(rawValue: section) == .detection ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .detection: return "Detection"
        case .recording: return "Recording"
        case .storage:   return "Storage"
        case .overlay:   return "Overlay"
        case .display:   return "Display"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .detection: return "Higher values detect smaller movements. Use Live Preview to tune against your actual terrarium."
        case .recording: return "Seconds to keep recording after motion stops, in case the animal moves again."
        case .storage:   return "Maximum video data per session. Set to Off for unlimited recording."
        case .overlay:   return "Show a rectangle around detected motion on screen and in recordings."
        case .display:   return "Seconds of inactivity before the screen dims to save battery."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        // Reset the cell so reused cells don't carry stale subviews
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.selectionStyle = .none
        cell.accessoryView = nil

        switch Section(rawValue: indexPath.section)! {

        case .detection:
            if indexPath.row == 0 {
                // Row 0: sensitivity slider
                cell.textLabel?.text = nil
                let label = UILabel()
                label.text = "Sensitivity"
                label.setContentHuggingPriority(.required, for: .horizontal)

                let stack = UIStackView(arrangedSubviews: [label, sensitivitySlider, sensitivityValueLabel])
                stack.axis = .horizontal
                stack.spacing = 12
                stack.alignment = .center
                stack.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    stack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                    stack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor)
                ])
            } else {
                // Row 1: live preview entry point — tappable, opens preview over camera feed
                cell.selectionStyle = .default
                cell.textLabel?.text = "Live Preview"
                let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                cell.imageView?.image = UIImage(systemName: "camera.viewfinder", withConfiguration: config)
                cell.imageView?.tintColor = .label
                cell.accessoryType = .disclosureIndicator
            }

        case .recording:
            // Post-motion tail row: label + value + stepper
            cell.textLabel?.text = nil
            let label = UILabel()
            label.text = "Post-Motion Tail"
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let stack = UIStackView(arrangedSubviews: [label, tailValueLabel, tailStepper])
            stack.axis = .horizontal
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor)
            ])

        case .storage:
            // Storage quota row: label + value + stepper
            cell.textLabel?.text = nil
            let label = UILabel()
            label.text = "Session Quota"
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let stack = UIStackView(arrangedSubviews: [label, quotaValueLabel, quotaStepper])
            stack.axis = .horizontal
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor)
            ])

        case .overlay:
            // Bounding box toggle row: label + switch
            cell.textLabel?.text = "Bounding Boxes"
            cell.accessoryView = boundingBoxSwitch

        case .display:
            // Dim delay row: label + value + stepper
            cell.textLabel?.text = nil
            let label = UILabel()
            label.text = "Dim Delay"
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let stack = UIStackView(arrangedSubviews: [label, dimValueLabel, dimStepper])
            stack.axis = .horizontal
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor)
            ])
        }

        return cell
    }
}
