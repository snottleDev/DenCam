# DenCam Development Log

This file tracks major milestones. Day-to-day session notes live in GitHub Issues labeled `dev-session`.

---

## Milestone 0 — Project Inception
**Date:** 2026-02-18

- App concept defined: night vision motion-triggered camera for terrarium animals
- Tech stack chosen: Swift, UIKit, AVFoundation, iOS 16+
- Core feature set agreed upon
- Post-v1.0 roadmap established
- Repository created
- CLAUDE.md boot file written
- Development methodology: Claude generates all code with heavy inline comments; developer reviews and runs

---

## Session 1 — Camera Preview
**Date:** 2026-02-18

- Installed XcodeGen, created `project.yml` (iOS 16, iPhone only, Swift 5)
- Built AppDelegate + SceneDelegate (programmatic, no storyboard)
- Built CameraManager: AVCaptureSession on dedicated serial queue, back camera, exposes preview layer
- Built ViewController: full-screen preview, permission denied label
- Added Info.plist with bundle keys, scene manifest, camera/mic usage strings
- Verified build on Simulator and live camera preview on physical iPhone

### Next Session Plan: Motion Detection with ROI

**New files:**
- `DenCam/Camera/MotionDetector.swift` — frame differencing on pixel buffers, ROI masking
- `DenCam/UI/ROIOverlayView.swift` — translucent overlay with 4 draggable corner handles
- `DenCam/Settings/SettingsStore.swift` — UserDefaults wrapper for ROI rect + sensitivity

**Modified files:**
- `CameraManager.swift` — add AVCaptureVideoDataOutput, delegate frames to MotionDetector
- `ViewController.swift` — add ROIOverlayView, wire up MotionDetector, green border flash on motion

**Sensitivity design:**
- Pixel threshold: 30 (hardcoded constant, filters sensor noise)
- Sensitivity slider: 0.0–1.0 (user-facing, default 0.5)
  - Maps internally: `areaThreshold = lerp(0.10, 0.002, sensitivity)`
  - 0.0 = least sensitive (~10% ROI change needed)
  - 1.0 = most sensitive (~0.2% ROI change triggers)
- Frame skip: every 5th frame (constant, easy to make configurable later)

---

<!-- Add new milestones above this line -->
