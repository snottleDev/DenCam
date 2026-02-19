import Foundation

// ThermalMonitor observes the device's thermal state via
// ProcessInfo.thermalStateDidChangeNotification and reports changes
// through a callback. ViewController uses this to warn the user at
// .serious and to stop recording at .critical to protect the device.
//
// Usage:
//   thermalMonitor.onStateChange = { state in … }
//   thermalMonitor.start()
//   // later:
//   thermalMonitor.stop()

class ThermalMonitor {

    // MARK: - Public Properties

    // Called on the main thread whenever the thermal state changes.
    var onStateChange: ((ProcessInfo.ThermalState) -> Void)?

    // The most recently observed thermal state.
    private(set) var currentState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    // MARK: - Public Methods

    /// Begin observing thermal state changes.
    func start() {
        // Read the current state immediately so the caller can act on it
        currentState = ProcessInfo.processInfo.thermalState

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        print("[ThermalMonitor] Started — current state: \(label(for: currentState))")
    }

    /// Stop observing. Safe to call even if start() was never called.
    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        print("[ThermalMonitor] Stopped")
    }

    // MARK: - Private

    @objc private func thermalStateDidChange() {
        let newState = ProcessInfo.processInfo.thermalState
        currentState = newState
        print("[ThermalMonitor] Thermal state changed → \(label(for: newState))")

        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }

    /// Human-readable label for logging.
    private func label(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
