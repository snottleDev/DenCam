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

    // MARK: - Section / Row Layout
    //
    // Each section groups related settings. Rows are identified by their
    // index within the section.

    private enum Section: Int, CaseIterable {
        case detection  // Sensitivity
        case recording  // Post-motion tail
        case storage    // Storage quota
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

        // Register a plain cell style for reuse
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
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
        // Each section has exactly one row
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .detection: return "Detection"
        case .recording: return "Recording"
        case .storage:   return "Storage"
        case .display:   return "Display"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .detection: return "How sensitive motion detection is. Higher values detect smaller movements."
        case .recording: return "Seconds to keep recording after motion stops, in case the animal moves again."
        case .storage:   return "Maximum video data per session. Set to Off for unlimited recording."
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
            // Sensitivity row: label + slider + percentage value
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
