import CoreVideo

class MotionDetector {

    // MARK: - Constants

    private let pixelThreshold: Int = 30
    private let frameSkip: Int = 5

    // MARK: - Public Properties

    var sensitivity: Float = 0.5
    var roiRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    var onMotionDetected: ((Bool) -> Void)?

    // MARK: - Private Properties

    private var previousBuffer: CVPixelBuffer?
    private var frameCount: Int = 0

    // MARK: - Core Method

    func processFrame(_ buffer: CVPixelBuffer) {
        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }

        defer { previousBuffer = buffer }

        guard let previous = previousBuffer else { return }

        // Lock both buffers
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        CVPixelBufferLockBaseAddress(previous, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(previous, .readOnly)
        }

        // Get the Y (luminance) plane — plane 0 of the biplanar YCbCr format
        guard let currentBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let previousBase = CVPixelBufferGetBaseAddressOfPlane(previous, 0) else {
            return
        }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let prevBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(previous, 0)

        let currentPtr = currentBase.assumingMemoryBound(to: UInt8.self)
        let previousPtr = previousBase.assumingMemoryBound(to: UInt8.self)

        // Convert normalized ROI to pixel coordinates
        let roiMinX = max(0, Int(roiRect.origin.x * CGFloat(width)))
        let roiMinY = max(0, Int(roiRect.origin.y * CGFloat(height)))
        let roiMaxX = min(width, Int((roiRect.origin.x + roiRect.size.width) * CGFloat(width)))
        let roiMaxY = min(height, Int((roiRect.origin.y + roiRect.size.height) * CGFloat(height)))

        let roiWidth = roiMaxX - roiMinX
        let roiHeight = roiMaxY - roiMinY
        guard roiWidth > 0, roiHeight > 0 else { return }

        let totalPixels = roiWidth * roiHeight
        var changedPixels = 0

        // Compare pixels in the ROI, sampling every 2nd pixel for performance
        for y in stride(from: roiMinY, to: roiMaxY, by: 2) {
            for x in stride(from: roiMinX, to: roiMaxX, by: 2) {
                let currentVal = Int(currentPtr[y * bytesPerRow + x])
                let previousVal = Int(previousPtr[y * prevBytesPerRow + x])
                let diff = abs(currentVal - previousVal)
                if diff > pixelThreshold {
                    changedPixels += 1
                }
            }
        }

        // Adjust total for the 2x2 sampling stride
        let sampledTotal = (roiWidth / 2) * (roiHeight / 2)
        guard sampledTotal > 0 else { return }

        let changedFraction = Float(changedPixels) / Float(sampledTotal)

        // Map sensitivity to area threshold: 0.10 at sensitivity=0 down to 0.002 at sensitivity=1
        let areaThreshold = 0.10 - (sensitivity * 0.098)

        let motionDetected = changedFraction >= areaThreshold
        onMotionDetected?(motionDetected)
    }
}
