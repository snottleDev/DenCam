import CoreVideo

class MotionDetector {

    // MARK: - Constants

    private let pixelThreshold: Int = 30
    private let frameSkip: Int = 5

    // MARK: - Public Properties

    var sensitivity: Float = 0.5
    var roiRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    var onMotionDetected: ((Bool) -> Void)?

    // Called with the bounding box (normalized 0–1, relative to full frame) of
    // all changed pixels, or nil when no motion is detected. Used for drawing
    // bounding boxes on screen and burning them into recorded video.
    var onMotionRegion: ((CGRect?) -> Void)?

    // MARK: - Private Properties

    // We store a COPY of the Y-plane luminance data rather than holding onto
    // the CVPixelBuffer itself. CVPixelBuffers come from a fixed-size pool in
    // AVFoundation — retaining them prevents the pool from reclaiming memory,
    // which causes unbounded memory growth and eventually an OS kill.
    private var previousLuminance: Data?
    private var previousWidth: Int = 0
    private var previousHeight: Int = 0
    private var previousBytesPerRow: Int = 0
    private var frameCount: Int = 0

    // MARK: - Core Method

    func processFrame(_ buffer: CVPixelBuffer) {
        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        // Get the Y (luminance) plane — plane 0 of the biplanar YCbCr format
        guard let currentBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return
        }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let planeSize = bytesPerRow * height

        let currentPtr = currentBase.assumingMemoryBound(to: UInt8.self)

        // Compare with previous frame if we have one
        if let prevData = previousLuminance,
           previousWidth == width,
           previousHeight == height {

            let prevBytesPerRow = previousBytesPerRow

            // Convert normalized ROI to pixel coordinates
            let roiMinX = max(0, Int(roiRect.origin.x * CGFloat(width)))
            let roiMinY = max(0, Int(roiRect.origin.y * CGFloat(height)))
            let roiMaxX = min(width, Int((roiRect.origin.x + roiRect.size.width) * CGFloat(width)))
            let roiMaxY = min(height, Int((roiRect.origin.y + roiRect.size.height) * CGFloat(height)))

            let roiWidth = roiMaxX - roiMinX
            let roiHeight = roiMaxY - roiMinY

            if roiWidth > 0, roiHeight > 0 {
                var changedPixels = 0

                // Track the bounding box of all changed pixels so we can
                // draw a rectangle around the motion region.
                var bbMinX = Int.max
                var bbMinY = Int.max
                var bbMaxX = Int.min
                var bbMaxY = Int.min

                // Compare pixels in the ROI, sampling every 2nd pixel for performance
                prevData.withUnsafeBytes { rawBuffer in
                    let previousPtr = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
                    for y in stride(from: roiMinY, to: roiMaxY, by: 2) {
                        for x in stride(from: roiMinX, to: roiMaxX, by: 2) {
                            let currentVal = Int(currentPtr[y * bytesPerRow + x])
                            let previousVal = Int(previousPtr[y * prevBytesPerRow + x])
                            let diff = abs(currentVal - previousVal)
                            if diff > pixelThreshold {
                                changedPixels += 1
                                if x < bbMinX { bbMinX = x }
                                if x > bbMaxX { bbMaxX = x }
                                if y < bbMinY { bbMinY = y }
                                if y > bbMaxY { bbMaxY = y }
                            }
                        }
                    }
                }

                // Adjust total for the 2x2 sampling stride
                let sampledTotal = (roiWidth / 2) * (roiHeight / 2)
                if sampledTotal > 0 {
                    let changedFraction = Float(changedPixels) / Float(sampledTotal)

                    // Map sensitivity to area threshold: 0.10 at sensitivity=0 down to 0.002 at sensitivity=1
                    let areaThreshold = 0.10 - (sensitivity * 0.098)
                    let motionDetected = changedFraction >= areaThreshold
                    onMotionDetected?(motionDetected)

                    // Emit the bounding box as normalized coordinates (0–1)
                    // relative to the full frame, so it's resolution-independent.
                    if motionDetected && bbMinX <= bbMaxX && bbMinY <= bbMaxY {
                        let normRect = CGRect(
                            x: CGFloat(bbMinX) / CGFloat(width),
                            y: CGFloat(bbMinY) / CGFloat(height),
                            width: CGFloat(bbMaxX - bbMinX) / CGFloat(width),
                            height: CGFloat(bbMaxY - bbMinY) / CGFloat(height)
                        )
                        onMotionRegion?(normRect)
                    } else {
                        onMotionRegion?(nil)
                    }
                }
            }
        }

        // Copy the Y-plane data so we can release the CVPixelBuffer back to the pool
        previousLuminance = Data(bytes: currentPtr, count: planeSize)
        previousWidth = width
        previousHeight = height
        previousBytesPerRow = bytesPerRow
    }
}
