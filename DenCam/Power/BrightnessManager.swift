import UIKit

class BrightnessManager {

    // MARK: - Properties

    private var dimTimer: Timer?
    private var isDimmed: Bool = false
    private var savedBrightness: CGFloat = 0.5
    private var dimDelay: TimeInterval

    // Black overlay to fully hide the screen — UIScreen.main.brightness = 0
    // still leaves a faint backlight glow, so we cover everything with an
    // opaque view on top.
    private var blackOverlay: UIView?
    private weak var hostView: UIView?

    // MARK: - Init

    init(dimDelay: TimeInterval = 30) {
        self.dimDelay = dimDelay
    }

    // MARK: - Public

    func start(in view: UIView) {
        hostView = view
        resetTimer()
    }

    func stop() {
        dimTimer?.invalidate()
        dimTimer = nil
        if isDimmed {
            restoreScreen()
        }
    }

    /// Called on any user touch. Returns `true` if the screen was dimmed
    /// (so the caller can swallow the touch instead of passing it to UI).
    @discardableResult
    func userDidTouch() -> Bool {
        let wasDimmed = isDimmed
        if isDimmed {
            restoreScreen()
        }
        resetTimer()
        return wasDimmed
    }

    // MARK: - Private

    private func resetTimer() {
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(
            withTimeInterval: dimDelay,
            repeats: false
        ) { [weak self] _ in
            self?.dimScreen()
        }
    }

    private func dimScreen() {
        guard let hostView = hostView else { return }

        savedBrightness = UIScreen.main.brightness
        isDimmed = true

        // Add opaque black overlay on top of all content
        let overlay = UIView(frame: hostView.bounds)
        overlay.backgroundColor = .black
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        overlay.isUserInteractionEnabled = false
        hostView.addSubview(overlay)
        blackOverlay = overlay

        UIView.animate(withDuration: 0.5) {
            overlay.alpha = 1
        }

        animateBrightness(to: 0)
    }

    private func restoreScreen() {
        isDimmed = false
        animateBrightness(to: savedBrightness)

        if let overlay = blackOverlay {
            UIView.animate(withDuration: 0.3, animations: {
                overlay.alpha = 0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
            blackOverlay = nil
        }
    }

    /// UIScreen.main.brightness isn't animatable, so step it over ~0.5s.
    private func animateBrightness(to target: CGFloat) {
        let current = UIScreen.main.brightness
        let steps = 20
        let stepDuration = 0.5 / Double(steps)
        let delta = (target - current) / CGFloat(steps)

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                // Use exact target on final step to avoid floating-point drift
                UIScreen.main.brightness = (i == steps) ? target : current + delta * CGFloat(i)
            }
        }
    }
}
