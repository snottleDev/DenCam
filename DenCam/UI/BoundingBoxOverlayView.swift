import UIKit

// BoundingBoxOverlayView draws a rectangle around the area where motion
// was detected. It sits on top of the camera preview and ROI overlay.
// The rect uses normalized coordinates (0–1) just like ROIOverlayView,
// so it's resolution-independent.
//
// This view is purely visual — it doesn't handle touches.

class BoundingBoxOverlayView: UIView {

    // MARK: - Public Properties

    // The normalized bounding box of detected motion. Set to nil to hide.
    var motionRect: CGRect? {
        didSet { updateLayer() }
    }

    // MARK: - Private Properties

    private let boxLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.systemYellow.cgColor
        layer.lineWidth = 2
        return layer
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(boxLayer)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayer()
    }

    // MARK: - Drawing

    private func updateLayer() {
        boxLayer.frame = bounds

        guard let rect = motionRect else {
            boxLayer.path = nil
            return
        }

        let pixelRect = CGRect(
            x: rect.origin.x * bounds.width,
            y: rect.origin.y * bounds.height,
            width: rect.size.width * bounds.width,
            height: rect.size.height * bounds.height
        )
        boxLayer.path = UIBezierPath(rect: pixelRect).cgPath
    }
}
