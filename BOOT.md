# DenCam — BOOT.md

Read this file at the start of every session to orient yourself before writing or modifying any code.

---

## What This App Does

DenCam is a paid iOS app that films terrarium animals at night using motion-triggered recording. The phone is left plugged in overnight. When motion is detected within a user-defined region, the app records video until a configurable number of seconds after the last detected motion. The app aggressively manages power, heat, and storage for long unattended sessions.

---

## Developer Context

- The human collaborator (snottleDev) is a beginner to iOS/Swift development.
- Claude is responsible for all code generation.
- All code must be heavily commented with inline explanations of *what* the code does and *why*.
- Prefer clarity over cleverness. If there are two ways to do something, choose the one that is easier to read.
- Never silently change architecture. If a structural decision needs to change, explain it first.
- **One writer rule**: Only Claude Code (terminal) makes commits and pushes to GitHub. Claude Desktop (browser) is read-only on the repository — it can plan and discuss but must not create, edit, or commit files.

---

## Tech Stack

- Language: Swift
- UI Framework: UIKit (not SwiftUI — the camera pipeline is AVFoundation-native and UIKit keeps the stack direct and debuggable)
- Camera: AVFoundation
- Minimum Deployment Target: iOS 16.0
- No third-party dependencies unless absolutely necessary and explicitly agreed upon

---

## Project Folder Structure

```
DenCam/
  AppDelegate.swift         # App lifecycle entry point
  SceneDelegate.swift       # Scene/window setup

  Camera/
    CameraManager.swift     # AVCaptureSession setup, start/stop, device config
    RecordingManager.swift  # AVAssetWriter recording logic, file output
    MotionDetector.swift    # Frame differencing logic, ROI masking, sensitivity threshold

  Power/
    ThermalMonitor.swift    # ProcessInfo.thermalState observation, callbacks
    BrightnessManager.swift # Screen dimming logic, motion/stillness detection for phone

  Storage/
    StorageManager.swift    # Quota enforcement, disk space checks, file size tracking
    PhotoLibrarySaver.swift # PHPhotoLibrary saving logic

  UI/
    ViewController.swift    # Main view controller, composes all modules
    ROIOverlayView.swift    # Draggable corner handles for Region of Interest rectangle
    BoundingBoxOverlayView.swift  # Toggleable overlay drawing boxes around detected motion
    SettingsViewController.swift  # User settings: tail duration, quota, schedule, sensitivity
    SensitivityPreviewViewController.swift  # Half-sheet live preview for sensitivity tuning

  Settings/
    SettingsStore.swift     # UserDefaults wrapper for all user preferences

  Notifications/
    NotificationManager.swift  # Local notification scheduling (morning summary)

Resources/
  Assets.xcassets
  Info.plist
```

---

## Key Architectural Decisions

**Motion Detection:** Frame differencing on pixel buffers from AVCaptureVideoDataOutput. Only pixels within the ROI rectangle are evaluated. A sensitivity threshold (user-adjustable) determines what delta counts as motion.

**Recording:** AVAssetWriter rather than AVCaptureMovieFileOutput — gives us frame-level control and is more robust for long sessions.

**Screen Dimming:** UIScreen.main.brightness set to 0 after CoreMotion detects the phone has been stationary for N seconds. Restored to previous brightness when the app is foregrounded intentionally.

**Thermal Management:** ProcessInfo.thermalStateDidChangeNotification observed at app level. At `.serious` — warn. At `.critical` — stop recording and display alert even at zero brightness (bump brightness briefly).

**Storage Quota:** User sets a max GB value. StorageManager tracks cumulative size of files written this session and halts new recordings when the quota is reached.

**ROI:** Normalized coordinates (0.0–1.0) stored in SettingsStore so they are resolution-independent. ROIOverlayView converts to screen points for display.

---

## Feature Status

### v1.0 Target
- [x] Camera preview (AVCaptureSession → CALayer)
- [x] Motion detection with ROI masking
- [x] Motion-triggered recording with configurable tail
- [x] Draggable ROI rectangle (4 corner handles)
- [x] Screen auto-dim on phone stillness
- [x] Thermal state monitoring and shutdown
- [x] Storage quota enforcement
- [x] Save to Photos library
- [x] Settings screen (tail duration, quota, sensitivity)

### Post-v1.0 Roadmap
- [ ] Scheduled recording window
- [x] Lock exposure / white balance
- [x] Morning summary local notification
- [x] Motion bounding box overlay (toggle)
- [x] Sensitivity slider with live preview
- [x] Arm/disarm button (prevent recording while positioning camera)

---

## Session Workflow

1. Read this file.
2. Check the open GitHub Issues labeled `dev-session` to understand what was last worked on.
3. Ask the developer what they want to work on today if not already specified.
4. Implement, explain, comment.
5. At end of session, help the developer update the open session Issue with a summary of what changed.

---

## App Store Notes

- Paid app, modest price point (TBD)
- Requires Apple Developer account ($99/yr) — developer does not yet have one
- Info.plist must include descriptive usage strings for camera and microphone permissions
- Privacy policy required before App Store submission
- No third-party analytics or ads
