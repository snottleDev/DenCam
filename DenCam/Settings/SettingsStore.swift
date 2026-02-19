import Foundation

class SettingsStore {

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let roiX = "roi_x"
        static let roiY = "roi_y"
        static let roiWidth = "roi_width"
        static let roiHeight = "roi_height"
        static let sensitivity = "sensitivity"
        static let postMotionTail = "post_motion_tail"
    }

    // MARK: - ROI (normalized 0.0–1.0)

    var roiRect: CGRect {
        get {
            // Return default if never saved (all values will be 0)
            guard defaults.object(forKey: Key.roiX) != nil else {
                return CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            }
            return CGRect(
                x: defaults.double(forKey: Key.roiX),
                y: defaults.double(forKey: Key.roiY),
                width: defaults.double(forKey: Key.roiWidth),
                height: defaults.double(forKey: Key.roiHeight)
            )
        }
        set {
            defaults.set(newValue.origin.x, forKey: Key.roiX)
            defaults.set(newValue.origin.y, forKey: Key.roiY)
            defaults.set(newValue.size.width, forKey: Key.roiWidth)
            defaults.set(newValue.size.height, forKey: Key.roiHeight)
        }
    }

    // MARK: - Sensitivity (0.0 least … 1.0 most, default 0.5)

    var sensitivity: Float {
        get {
            guard defaults.object(forKey: Key.sensitivity) != nil else {
                return 0.5
            }
            return defaults.float(forKey: Key.sensitivity)
        }
        set {
            defaults.set(newValue, forKey: Key.sensitivity)
        }
    }

    // MARK: - Post-Motion Tail (seconds, default 10.0)
    // How long to keep recording after motion stops, in case the animal moves again.

    var postMotionTail: TimeInterval {
        get {
            guard defaults.object(forKey: Key.postMotionTail) != nil else {
                return 10.0
            }
            return defaults.double(forKey: Key.postMotionTail)
        }
        set {
            defaults.set(newValue, forKey: Key.postMotionTail)
        }
    }
}
