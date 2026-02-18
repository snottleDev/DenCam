import UIKit

class ROIOverlayView: UIView {

    // MARK: - Public Properties

    var roiRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) {
        didSet { updateLayers() }
    }

    var isMotionDetected: Bool = false {
        didSet { updateBorderColor() }
    }

    var onROIChanged: ((CGRect) -> Void)?

    // MARK: - Private Properties

    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var cornerHandles: [UIView] = []
    private let handleSize: CGFloat = 28

    // Minimum ROI size as fraction of view dimensions
    private let minROIFraction: CGFloat = 0.10

    // Track which corner is being dragged (0=topLeft, 1=topRight, 2=bottomLeft, 3=bottomRight)
    private var activeCorner: Int?

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
        isUserInteractionEnabled = true
        backgroundColor = .clear

        // Dark mask with ROI cutout
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        layer.addSublayer(maskLayer)

        // ROI border
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.green.withAlphaComponent(0.6).cgColor
        borderLayer.lineWidth = 2
        layer.addSublayer(borderLayer)

        // Create 4 corner handles
        for _ in 0..<4 {
            let handle = UIView()
            handle.backgroundColor = .white
            handle.layer.cornerRadius = handleSize / 2
            handle.layer.shadowColor = UIColor.black.cgColor
            handle.layer.shadowOpacity = 0.5
            handle.layer.shadowOffset = CGSize(width: 0, height: 1)
            handle.layer.shadowRadius = 2
            addSubview(handle)
            cornerHandles.append(handle)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayers()
    }

    // MARK: - Layer Updates

    private func updateLayers() {
        let roiPixelRect = pixelRect(from: roiRect)

        // Mask: full view path with ROI cutout (even-odd fill)
        let fullPath = UIBezierPath(rect: bounds)
        fullPath.append(UIBezierPath(rect: roiPixelRect))
        maskLayer.path = fullPath.cgPath
        maskLayer.frame = bounds

        // Border around ROI
        borderLayer.path = UIBezierPath(rect: roiPixelRect).cgPath
        borderLayer.frame = bounds

        // Position corner handles
        let corners = cornerPoints(of: roiPixelRect)
        for (i, handle) in cornerHandles.enumerated() {
            handle.frame = CGRect(
                x: corners[i].x - handleSize / 2,
                y: corners[i].y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
        }
    }

    private func updateBorderColor() {
        if isMotionDetected {
            borderLayer.strokeColor = UIColor.green.cgColor
            borderLayer.lineWidth = 4
        } else {
            borderLayer.strokeColor = UIColor.green.withAlphaComponent(0.6).cgColor
            borderLayer.lineWidth = 2
        }
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // Find the closest corner handle within touch distance
            activeCorner = nil
            let corners = cornerPoints(of: pixelRect(from: roiRect))
            for (i, point) in corners.enumerated() {
                if hypot(location.x - point.x, location.y - point.y) < handleSize * 1.5 {
                    activeCorner = i
                    break
                }
            }

        case .changed:
            guard let corner = activeCorner else { return }
            let normalizedX = location.x / bounds.width
            let normalizedY = location.y / bounds.height
            var newRect = roiRect

            let minW = minROIFraction
            let minH = minROIFraction

            switch corner {
            case 0: // top-left
                let maxX = newRect.maxX - minW
                let maxY = newRect.maxY - minH
                let clampedX = min(max(normalizedX, 0), maxX)
                let clampedY = min(max(normalizedY, 0), maxY)
                newRect.size.width += newRect.origin.x - clampedX
                newRect.size.height += newRect.origin.y - clampedY
                newRect.origin.x = clampedX
                newRect.origin.y = clampedY

            case 1: // top-right
                let minX = newRect.origin.x + minW
                let maxY = newRect.maxY - minH
                let clampedX = min(max(normalizedX, minX), 1.0)
                let clampedY = min(max(normalizedY, 0), maxY)
                newRect.size.width = clampedX - newRect.origin.x
                newRect.size.height += newRect.origin.y - clampedY
                newRect.origin.y = clampedY

            case 2: // bottom-left
                let maxX = newRect.maxX - minW
                let minY = newRect.origin.y + minH
                let clampedX = min(max(normalizedX, 0), maxX)
                let clampedY = min(max(normalizedY, minY), 1.0)
                newRect.size.width += newRect.origin.x - clampedX
                newRect.size.height = clampedY - newRect.origin.y
                newRect.origin.x = clampedX

            case 3: // bottom-right
                let minX = newRect.origin.x + minW
                let minY = newRect.origin.y + minH
                let clampedX = min(max(normalizedX, minX), 1.0)
                let clampedY = min(max(normalizedY, minY), 1.0)
                newRect.size.width = clampedX - newRect.origin.x
                newRect.size.height = clampedY - newRect.origin.y

            default:
                break
            }

            roiRect = newRect

        case .ended, .cancelled:
            if activeCorner != nil {
                onROIChanged?(roiRect)
            }
            activeCorner = nil

        default:
            break
        }
    }

    // MARK: - Helpers

    private func pixelRect(from normalized: CGRect) -> CGRect {
        return CGRect(
            x: normalized.origin.x * bounds.width,
            y: normalized.origin.y * bounds.height,
            width: normalized.size.width * bounds.width,
            height: normalized.size.height * bounds.height
        )
    }

    private func cornerPoints(of rect: CGRect) -> [CGPoint] {
        return [
            CGPoint(x: rect.minX, y: rect.minY),     // top-left
            CGPoint(x: rect.maxX, y: rect.minY),     // top-right
            CGPoint(x: rect.minX, y: rect.maxY),     // bottom-left
            CGPoint(x: rect.maxX, y: rect.maxY)      // bottom-right
        ]
    }
}
