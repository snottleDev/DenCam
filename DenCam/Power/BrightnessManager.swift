import UIKit

class BrightnessManager {

    // MARK: - Properties

    private var dimTimer: Timer?
    private var isDimmed: Bool = false
    private var savedBrightness: CGFloat = 0.5
    private var dimDelay: TimeInterval

    // MARK: - Init

    init(dimDelay: TimeInterval = 30) {
        self.dimDelay = dimDelay
    }

    // MARK: - Public

    func start() {
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
        savedBrightness = UIScreen.main.brightness
        isDimmed = true
        animateBrightness(to: 0)
    }

    private func restoreScreen() {
        isDimmed = false
        animateBrightness(to: savedBrightness)
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
