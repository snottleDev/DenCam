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

## Session 2 — Screen Dimming, Settings UI, Thermal, Storage, Bounding Boxes
**Date:** 2026-02-19

Completed all remaining v1.0 features and one post-v1.0 item.

### Screen Auto-Dim (`Power/BrightnessManager.swift`)
- Fades screen brightness to zero after 30s of no touches (configurable)
- Any tap restores brightness; wake-up taps are swallowed (don't trigger ROI changes)
- Stepped brightness animation over 0.5s (UIScreen.main.brightness isn't animatable)
- Added opaque black UIView overlay to fully hide screen — brightness=0 still leaves faint backlight glow
- Dragging ROI corners resets the dim timer

### Settings Screen (`UI/SettingsViewController.swift`)
- UITableViewController with `.insetGrouped` style — standard iOS Settings look
- Sections: Detection (sensitivity slider), Recording (tail stepper 5–60s), Storage (quota stepper 0–20 GB), Overlay (bounding box toggle), Display (dim delay stepper 10–120s)
- Gear button (⚙︎) on camera view opens settings as a modal sheet
- Values persist to UserDefaults via SettingsStore, re-applied on dismiss

### Thermal Monitoring (`Power/ThermalMonitor.swift`)
- Observes `ProcessInfo.thermalStateDidChangeNotification`
- `.serious` → warning label at bottom of screen, recording continues
- `.critical` → stops recording, saves current file, wakes screen so user sees the warning
- New recordings blocked during thermal shutdown; resumes when device cools

### Storage Quota (`Storage/StorageManager.swift`)
- Tracks cumulative bytes of video saved per session
- New recordings blocked when user's quota exceeded (default 5 GB, 0 = unlimited)
- File sizes tracked via `trackFile(at:)` when RecordingManager completes a file

### Motion Bounding Box Overlay (`UI/BoundingBoxOverlayView.swift`)
- MotionDetector enhanced to track min/max X/Y of changed pixels → normalized bounding box
- New `onMotionRegion` callback alongside existing boolean `onMotionDetected`
- Yellow CAShapeLayer rectangle drawn on live preview
- RecordingManager burns boxes into video via CIContext + CoreGraphics when enabled
- Two recording paths: toggle OFF = direct CMSampleBuffer (zero overhead), toggle ON = pixel buffer adaptor with compositing
- Toggle in Settings > Overlay > Bounding Boxes (default off)

### Files Created
- `DenCam/Power/BrightnessManager.swift`
- `DenCam/Power/ThermalMonitor.swift`
- `DenCam/Storage/StorageManager.swift`
- `DenCam/UI/SettingsViewController.swift`
- `DenCam/UI/BoundingBoxOverlayView.swift`

### Files Modified
- `DenCam/Camera/MotionDetector.swift` — bounding box tracking
- `DenCam/Camera/RecordingManager.swift` — CIContext/pixel buffer adaptor for box burn-in
- `DenCam/Settings/SettingsStore.swift` — dimDelay, storageQuotaGB, showBoundingBoxes
- `DenCam/UI/ViewController.swift` — wired all new managers, settings button, touch handling
- `BOOT.md` — all v1.0 checkboxes checked, bounding box overlay checked

### Status
All v1.0 features complete. Bounding box overlay (post-v1.0) also done. Remaining post-v1.0: scheduled recording window, lock exposure/white balance, morning summary notification, sensitivity slider with live preview.

---

## Session 3 — Exposure Lock, Morning Summary, Sensitivity Live Preview
**Date:** 2026-02-23

Three post-v1.0 features completed in one session. Only the scheduled recording window remains on the roadmap.

### Lock Exposure & White Balance (`Camera/CameraManager.swift`, `UI/ViewController.swift`)
- Stored `captureDevice` reference after session setup so it can be locked later
- `lockExposureAndWhiteBalance()` / `unlockExposureAndWhiteBalance()` — run on sessionQueue, completion on main thread
- Lock button (lock.open.fill / lock.fill) added top-left, mirroring the gear button top-right
- Starts disabled until camera is configured; turns yellow when locked
- Brief toast label fades in/out to confirm lock/unlock action

### Morning Summary Notification (`Notifications/NotificationManager.swift`, `UI/ViewController.swift`)
- New `MotionEvent` struct (start, end, computed duration) — one per completed recording clip
- `requestPermission()` called once after camera configures (iOS shows system dialog exactly once)
- `scheduleMorningSummary(events:totalBytes:)` cancels pending summary and reschedules for next 7:00 AM via `UNCalendarNotificationTrigger`
- Notification subtitle: event count + storage used + total duration
- Notification body: timestamp log, one line per clip — "2:34 AM – 2:36 AM (2m)". Capped at 20 events
- `currentRecordingStart` stamped when recording begins; `logMotionEvent(start:end:)` dispatched to main thread from both `handleTailExpired` and thermal shutdown paths
- Notification rescheduled after each clip so it always reflects the full night's activity

### Sensitivity Slider with Live Preview (`UI/SensitivityPreviewViewController.swift`, `UI/SettingsViewController.swift`, `UI/ViewController.swift`)
- New `SensitivityPreviewViewController` — compact sheet presented at medium detent (half-height), leaving camera feed visible above
- Contains: slider + percentage label, More/Less scale labels, motion indicator pill (grey/green), hint text
- Motion indicator driven by `setMotionActive(_:)`, called from the existing `onMotionDetected` callback in ViewController
- Accessed via Settings > Detection > "Live Preview" row (camera.viewfinder icon, disclosure indicator)
- Settings dismisses itself before presenting preview so camera is fully unobscured
- Every slider tick pushes sensitivity to both `MotionDetector` and `SettingsStore` in real time
- Bounding box overlay temporarily forced visible during preview regardless of user toggle; restored on Done

### Files Created
- `DenCam/Notifications/NotificationManager.swift`
- `DenCam/UI/SensitivityPreviewViewController.swift`

### Files Modified
- `DenCam/Camera/CameraManager.swift` — captureDevice reference, lockExposureAndWhiteBalance, unlockExposureAndWhiteBalance
- `DenCam/UI/ViewController.swift` — lock button + toast, session event log, notification wiring, sensitivity preview flow
- `DenCam/UI/SettingsViewController.swift` — Live Preview row, didSelectRowAt, onOpenSensitivityPreview callback

### Status
All post-v1.0 features complete except: scheduled recording window. App is otherwise feature-complete. Remaining before App Store: Developer account ($99/yr), privacy policy, full device provisioning.

---

<!-- Add new milestones above this line -->
